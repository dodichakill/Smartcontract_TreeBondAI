# TreeBond AI — Smart Contracts

Smart contract layer untuk **TreeBond AI** (lihat `../treebondai/prd.md`), dibangun dengan **Foundry**,
**Solidity 0.8.24**, dan **OpenZeppelin Contracts v5**, ditargetkan untuk **Arbitrum Sepolia (chain ID 421614)**.

Mengimplementasikan loop inti PRD:

```
Register -> Verify -> Tokenize -> Sponsor -> Monitor -> Verify Again
```

## Kontrak

| Kontrak | Tanggung jawab | Fungsi utama |
| --- | --- | --- |
| `src/TreeRegistry.sol` | Project + identitas tree, status lifecycle, metadata CID | `createProject`, `registerTree`, `updateTreeStatus`, `updateTreeMetadata`, `markSponsored`, `getTree`, `getProject` |
| `src/TreeNFT.sol` | ERC-721 ownership per tree (tokenId = treeId) | `mint`, `tokenURI`, `transferFrom` |
| `src/TreeBond.sol` | Sponsorship, pembayaran native ETH, platform fee, payout operator | `sponsorTree`, `getTreePrice`, `setTreePrice`, `withdraw` |
| `src/VerificationRegistry.sol` | Rekaman verifikasi on-chain (hash + CID + skor) oleh oracle | `submitVerification`, `getVerification`, `getLatestVerification` |

Pemetaan PRD: §38–§44 (arsitektur kontrak, events), §90–§93 (spesifikasi MVP & testing),
§21–§22 (tree lifecycle / state machine), §31–§36 & §64–§65 (skor verifikasi, evidence hash),
§95 (integration test), §110 (demo hardening).

## Peran (AccessControl)

| Role | Deskripsi |
| --- | --- |
| `DEFAULT_ADMIN_ROLE` | Admin kontrak (grant/revoke role, set treasury & fee) |
| `OPERATOR_ROLE` | Buat project, registrasi tree, update metadata, set harga |
| `VERIFIER_ROLE` | Update status tree terkait verifikasi/dispute |
| `ORACLE_ROLE` | Submit hasil verifikasi on-chain (`VerificationRegistry`) |
| `SPONSOR_ROLE` | Diberikan ke `TreeBond` untuk menandai tree `SPONSORED` |
| `MINTER_ROLE` | Diberikan ke `TreeBond` untuk mint `TreeNFT` |
| `PAUSER_ROLE` | Pause/unpause kontrak |

## Struktur

```
treebondai-smartcontract/
├── foundry.toml
├── Makefile
├── .env.example
├── src/
│   ├── TreeRegistry.sol
│   ├── TreeNFT.sol
│   ├── TreeBond.sol
│   ├── VerificationRegistry.sol
│   └── interfaces/
├── test/                  # 71 tests: unit, fuzz, dan integrasi lifecycle
├── script/
│   ├── Deploy.s.sol       # deploy + role wiring + tulis deployments/<network>.json
│   └── Export.s.sol       # tulis exports/addresses.ts + addresses.json
├── deployments/           # hasil deploy (dibuat otomatis)
└── exports/               # ABI + addresses untuk frontend (dibuat otomatis)
```

## Prasyarat

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Di mesin ini, binary Foundry ada di `~/.foundry/bin` dan **ter-shadow oleh Laravel Forge CLI milik Herd**.
  Semua target `make` sudah memakai path absolut `$(HOME)/.foundry/bin/forge`, tetapi jika memanggil `forge`
  manual, gunakan:

  ```bash
  export PATH="$HOME/.foundry/bin:$PATH"
  forge --version   # pastikan output "forge Version: ..." bukan "Forge CLI"
  ```

## Build & Test

```bash
make build          # forge build
make sizes          # cek ukuran kontrak (< 24 KB)
make test           # 71 tests
make test-v         # verbose
make coverage       # butuh lcov (opsional)
make fmt            # forge fmt
```

## Konfigurasi

```bash
cp .env.example .env
```

| Variable | Keterangan |
| --- | --- |
| `PRIVATE_KEY` | Private key deployer (alternatif: pakai keystore, lihat bawah) |
| `ARBITRUM_SEPOLIA_RPC_URL` | Default `https://sepolia-rollup.arbitrum.io/rpc` |
| `ARBISCAN_API_KEY` | API key [Arbiscan](https://arbiscan.io/myapikey) untuk verify kontrak |
| `TREASURY_ADDRESS` | Penerima platform fee (default: deployer) |
| `ORACLE_ADDRESS` | Penerima `ORACLE_ROLE` (default: deployer) |
| `PLATFORM_FEE_BPS` | Platform fee basis points, max `2000` = 20% (default: `1000` = 10%) |
| `DEFAULT_TREE_PRICE_WEI` | Harga sponsorship default dalam wei (default: `1000000000000000` = 0.001 ETH) |

`PRIVATE_KEY` dan `ARBISCAN_API_KEY` **tidak pernah** ikut ter-commit (`.env` sudah di-gitignore).

Alternatif tanpa private key di file — gunakan keystore Foundry:

```bash
cast wallet import deployer --interactive   # buat keystore baru / import
make deploy-sepolia ACCOUNT=deployer        # akan meminta password keystore
```

## Deploy ke Arbitrum Sepolia

1. Siapkan saldo SepoliaETH di jaringan Arbitrum Sepolia
   ([Chainlink Faucet](https://faucets.chain.link/arbitrum-sepolia) atau faucet lainnya).
2. Simulasi dulu (tanpa broadcast):

   ```bash
   make deploy-dry-run
   ```

3. Deploy + verify:

   ```bash
   make deploy-sepolia                  # pakai PRIVATE_KEY dari .env
   make deploy-sepolia ACCOUNT=deployer # atau pakai keystore
   ```

   Script akan:
   - mendeploy `TreeRegistry`, `TreeNFT`, `VerificationRegistry`, `TreeBond`;
   - memberikan role yang dibutuhkan (`SPONSOR_ROLE` & `MINTER_ROLE` ke `TreeBond`, `ORACLE_ROLE` ke oracle);
   - menulis `deployments/arbitrum-sepolia.json`;
   - memverifikasi kontrak di Arbiscan bila `ARBISCAN_API_KEY` diisi.

## Export ABI & Addresses untuk Frontend

```bash
make export                # ABI -> exports/abi/*.json, addresses -> exports/addresses.ts
make export-abi            # hanya ABI
make export-addresses      # hanya addresses (butuh deployments/<network>.json)
```

`exports/addresses.ts`:

```ts
export const CHAIN_ID = 421614 as const;

export const CONTRACTS = {
  treeRegistry: "0x...",
  treeNFT: "0x...",
  treeBond: "0x...",
  verificationRegistry: "0x...",
} as const;
```

## Grant Role Setelah Deploy

```bash
export RPC=https://sepolia-rollup.arbitrum.io/rpc
export REGISTRY=0x... # dari deployments/arbitrum-sepolia.json

# operator (registrasi tree)
cast send $REGISTRY "grantRole(bytes32,address)" \
  $(cast keccak "OPERATOR_ROLE") 0xOperatorAddress --rpc-url $RPC --account deployer

# verifier
cast send $REGISTRY "grantRole(bytes32,address)" \
  $(cast keccak "VERIFIER_ROLE") 0xVerifierAddress --rpc-url $RPC --account deployer

# oracle (submit verifikasi)
cast send 0xVerificationRegistry "grantRole(bytes32,address)" \
  $(cast keccak "ORACLE_ROLE") 0xOracleAddress --rpc-url $RPC --account deployer
```

## Lifecycle & Events

```
REGISTERED -> PENDING_VERIFICATION -> VERIFIED -> AVAILABLE -> SPONSORED -> MONITORING -> MATURE
MONITORING/MATURE -> DEAD -> REPLACED
ANY (aktif) -> DISPUTED
PENDING_VERIFICATION -> REJECTED
```

Events indexing (persis PRD §44):

```solidity
event ProjectCreated(uint256 indexed projectId, address indexed operator, string code);
event TreeRegistered(uint256 indexed treeId, uint256 indexed projectId);
event TreeMinted(uint256 indexed treeId, uint256 indexed tokenId, address owner);
event TreeSponsored(uint256 indexed treeId, address indexed sponsor);
event VerificationSubmitted(uint256 indexed treeId, uint256 timestamp, bytes32 evidenceHash);
event TreeStatusChanged(uint256 indexed treeId, TreeStatus status);
```

Tambahan untuk kebutuhan indexer/frontend: `TreePayment`, `TreePriceSet`, `TreeMetadataUpdated`,
`VerificationRecorded`, `Withdrawal`, dan event standar ERC-721.

## Model Pembayaran

- Sponsorship dibayar dengan **native ETH (SepoliaETH)** sesuai `getTreePrice(treeId)`
  (harga per-tree, fallback ke `defaultTreePrice`).
- `platformFeeBps` dipotong ke `treasury`; sisanya menjadi hak `operator` project.
- Pembayaran memakai **pull pattern**: dana dikreditkan ke `pendingWithdrawals` lalu ditarik
  dengan `withdraw()` / `withdrawTo(address)`.
- `TreeBond` tidak memiliki `receive()`, jadi tidak ada ETH nyasar yang tertahan.

## Alamat Deployment

| Network | Chain ID | TreeRegistry | TreeNFT | TreeBond | VerificationRegistry |
| --- | --- | --- | --- | --- | --- |
| Arbitrum Sepolia | 421614 | _belum di-deploy_ | _belum di-deploy_ | _belum di-deploy_ | _belum di-deploy_ |

Setelah deploy, isi tabel ini dari `deployments/arbitrum-sepolia.json`.

## Security Notes

- Semua kontrak **non-upgradeable**, memakai `Pausable`, `AccessControl`, `ReentrancyGuard` (TreeBond), dan
  custom errors.
- `submitVerification` hanya untuk `ORACLE_ROLE` + proteksi replay per tree (`evidenceHash` duplikat ditolak).
- On-chain hanya menyimpan data minimal sesuai prinsip "on-chain minimalism" PRD §5.4:
  code/CID/hash/score/status — tanpa data pribadi.
- `sponsorTree` memakai exact payment (tidak menerima lebih/kurang) untuk mencegah kesalahan nominal.
- Deploy production (Arbitrum One) menunggu audit & legal review (PRD §92).
