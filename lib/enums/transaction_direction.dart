/// 一笔交易相对当前钱包的方向：转出 / 转入。
///
/// 本地记录目前只可能是 [outgoing]——只有本机发起的交易才会被记下来；
/// [incoming] 留给后续接入区块浏览器 API 后合并进来的收款记录。
enum TransactionDirection { outgoing, incoming }
