/// Bitcoin 地址脚本类型：同一助记词下，选哪种就决定了派生路径与地址编码形式。
/// 切换它会得到一组完全不同的地址，老地址上的资产不会自动跟过来。
enum BtcScriptType {
  /// BIP44 / P2PKH，路径 m/44'/coin'/0'/0/0，legacy 地址（主网 1…，测试网 m… n…）。
  p2pkh,

  /// BIP84 / P2WPKH，路径 m/84'/coin'/0'/0/0，原生 SegWit 地址（bc1q… / tb1q…）。
  p2wpkh,

  /// BIP86 / P2TR，路径 m/86'/coin'/0'/0/0，Taproot 单签地址（bc1p… / tb1p…）。
  /// 仅派生与收款可用；花费需 Schnorr + BIP341 签名，本项目尚未实现。
  p2tr,
}
