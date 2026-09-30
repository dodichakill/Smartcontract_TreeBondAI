// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { TreeRegistry } from "../src/TreeRegistry.sol";
import { TreeNFT } from "../src/TreeNFT.sol";
import { TreeBond } from "../src/TreeBond.sol";
import { VerificationRegistry } from "../src/VerificationRegistry.sol";

contract Deploy is Script {
    struct Deployment {
        address treeRegistry;
        address treeNFT;
        address treeBond;
        address verificationRegistry;
    }

    function run() external returns (Deployment memory deployment) {
        address deployer = msg.sender;
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        address oracle = vm.envOr("ORACLE_ADDRESS", deployer);
        uint256 platformFeeBps = vm.envOr("PLATFORM_FEE_BPS", uint256(1_000));
        uint256 defaultTreePrice = vm.envOr("DEFAULT_TREE_PRICE_WEI", uint256(0.001 ether));

        require(platformFeeBps <= 2_000, "PLATFORM_FEE_BPS above max (2000)");

        vm.startBroadcast();

        TreeRegistry treeRegistry = new TreeRegistry();
        TreeNFT treeNFT = new TreeNFT(address(treeRegistry));
        VerificationRegistry verificationRegistry = new VerificationRegistry(address(treeRegistry));
        TreeBond treeBond = new TreeBond(address(treeRegistry), address(treeNFT), treasury, uint16(platformFeeBps));

        treeRegistry.grantRole(treeRegistry.OPERATOR_ROLE(), deployer);
        treeRegistry.grantRole(treeRegistry.VERIFIER_ROLE(), deployer);
        treeRegistry.grantRole(treeRegistry.PAUSER_ROLE(), deployer);
        treeRegistry.grantRole(treeRegistry.SPONSOR_ROLE(), address(treeBond));

        treeNFT.grantRole(treeNFT.MINTER_ROLE(), address(treeBond));
        treeNFT.grantRole(treeNFT.PAUSER_ROLE(), deployer);

        verificationRegistry.grantRole(verificationRegistry.ORACLE_ROLE(), oracle);
        verificationRegistry.grantRole(verificationRegistry.PAUSER_ROLE(), deployer);

        treeBond.grantRole(treeBond.OPERATOR_ROLE(), deployer);
        treeBond.grantRole(treeBond.PAUSER_ROLE(), deployer);
        treeBond.setDefaultTreePrice(defaultTreePrice);

        vm.stopBroadcast();

        deployment = Deployment({
            treeRegistry: address(treeRegistry),
            treeNFT: address(treeNFT),
            treeBond: address(treeBond),
            verificationRegistry: address(verificationRegistry)
        });

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) || vm.isContext(VmSafe.ForgeContext.ScriptResume)) {
            _writeDeployment(deployment);
        }

        console2.log("TreeRegistry:", deployment.treeRegistry);
        console2.log("TreeNFT:", deployment.treeNFT);
        console2.log("TreeBond:", deployment.treeBond);
        console2.log("VerificationRegistry:", deployment.verificationRegistry);
        console2.log("Deployer:", deployer);
        console2.log("Treasury:", treasury);
        console2.log("Oracle:", oracle);
        console2.log("Platform fee (bps):", platformFeeBps);
        console2.log("Default tree price (wei):", defaultTreePrice);
    }

    function _writeDeployment(Deployment memory deployment) internal {
        string memory objectKey = "deployment";

        vm.serializeUint(objectKey, "chainId", block.chainid);
        vm.serializeUint(objectKey, "deployedAt", block.timestamp);
        vm.serializeAddress(objectKey, "TreeRegistry", deployment.treeRegistry);
        vm.serializeAddress(objectKey, "TreeNFT", deployment.treeNFT);
        vm.serializeAddress(objectKey, "TreeBond", deployment.treeBond);
        string memory json = vm.serializeAddress(objectKey, "VerificationRegistry", deployment.verificationRegistry);

        vm.writeJson(json, string.concat("deployments/", _networkName(), ".json"));
    }

    function _networkName() internal view returns (string memory) {
        if (block.chainid == 421_614) return "arbitrum-sepolia";
        if (block.chainid == 421_61) return "arbitrum-one";
        if (block.chainid == 31_337) return "anvil";
        return vm.toString(block.chainid);
    }
}
