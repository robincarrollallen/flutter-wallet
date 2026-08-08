import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'import_wallet_logic.dart';

/// 导入页视图模型（不可变）：持有要展示的导入入口列表，
/// 让 view 只 watch 一个 provider，数据与视图解耦。
class ImportWalletState {
  const ImportWalletState({required this.options});

  final List<ImportOption> options;
}

/// 导入页只读视图模型。数据来自 [ImportWalletLogic]，
/// 后续若要按地区/开关动态过滤入口，只改这里即可。
final importWalletStateProvider = Provider<ImportWalletState>((ref) {
  return const ImportWalletState(options: ImportWalletLogic.options);
});
