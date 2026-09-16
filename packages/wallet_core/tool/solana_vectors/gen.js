// 用 @solana/web3.js（与被测代码完全独立的实现）生成 Solana 交易级已知向量。
const web3 = require('@solana/web3.js');
const { getAssociatedTokenAddressSync, TOKEN_PROGRAM_ID, TOKEN_2022_PROGRAM_ID } = require('@solana/spl-token');

const seed = Buffer.from(Array.from({ length: 32 }, (_, i) => i + 1));
const payer = web3.Keypair.fromSeed(seed);

// 固定收款方：同样用确定性 seed 生成，避免向量依赖任何随机来源。
const recipientSeed = Buffer.from(Array.from({ length: 32 }, (_, i) => 255 - i));
const recipient = web3.Keypair.fromSeed(recipientSeed);

// 固定 blockhash：取一个确定的 32 字节值并按 base58 编码，不查链。
const blockhashBytes = Buffer.from(Array.from({ length: 32 }, (_, i) => (i * 3 + 7) % 256));
const recentBlockhash = web3.PublicKey.decode
  ? null
  : null;
const bs58 = require('bs58');
const blockhash = bs58.default ? bs58.default.encode(blockhashBytes) : bs58.encode(blockhashBytes);

// 指令组成必须和生产代码的 _buildTransaction 完全一致：两条 ComputeBudget + 一条 transfer。
// 少一条，向量就只验证了一个生产里并不存在的交易形态。
const COMPUTE_UNIT_LIMIT = 600;
const COMPUTE_UNIT_PRICE = 1000n;

const tx = new web3.Transaction({ feePayer: payer.publicKey, recentBlockhash: blockhash }).add(
  web3.ComputeBudgetProgram.setComputeUnitLimit({ units: COMPUTE_UNIT_LIMIT }),
  web3.ComputeBudgetProgram.setComputeUnitPrice({ microLamports: COMPUTE_UNIT_PRICE }),
  web3.SystemProgram.transfer({
    fromPubkey: payer.publicKey,
    toPubkey: recipient.publicKey,
    lamports: 1000000,
  }),
);
tx.sign(payer);

const message = tx.compileMessage().serialize();
const signature = tx.signature;

// SPL ATA：最容易回归的一处，用官方 spl-token 独立推导。
const mint = new web3.PublicKey('EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'); // USDC mainnet
const ata = getAssociatedTokenAddressSync(mint, payer.publicKey, false, TOKEN_PROGRAM_ID);
const ata2022 = getAssociatedTokenAddressSync(mint, payer.publicKey, false, TOKEN_2022_PROGRAM_ID);

console.log(JSON.stringify({
  generator: '@solana/web3.js ' + require('@solana/web3.js/package.json').version +
             ' + @solana/spl-token ' + JSON.parse(require('fs').readFileSync('node_modules/@solana/spl-token/package.json')).version,
  seedHex: seed.toString('hex'),
  payerPubkey: payer.publicKey.toBase58(),
  recipientSeedHex: recipientSeed.toString('hex'),
  recipientPubkey: recipient.publicKey.toBase58(),
  blockhashBytesHex: blockhashBytes.toString('hex'),
  blockhashBase58: blockhash,
  lamports: 1000000,
  computeUnitLimit: COMPUTE_UNIT_LIMIT,
  computeUnitPrice: COMPUTE_UNIT_PRICE.toString(),
  messageHex: Buffer.from(message).toString('hex'),
  signatureHex: Buffer.from(signature).toString('hex'),
  mint: mint.toBase58(),
  ataTokenProgram: ata.toBase58(),
  ataToken2022: ata2022.toBase58(),
}, null, 2));
