import 'dart:io';

import '../../../../domain/wallet.dart';

/// 备份方式选择（手动 / 云）。区别于领域层的 [BackupMethod]（含具体云 provider）。
enum BackupChoice { manual, cloud }

/// 备份方式选择页的纯逻辑：与平台相关的云备份文案 / 方式，不依赖 UI / 状态。
class BackupMethodLogic {
  const BackupMethodLogic._();

  /// 当前平台的云服务名称：iOS=iCloud，Android=Google 云端硬盘，其它=云端。
  static String cloudServiceName() {
    if (Platform.isIOS || Platform.isMacOS) return 'iCloud';
    if (Platform.isAndroid) return 'Google 云端硬盘';
    return '云端';
  }

  /// 当前平台对应的云备份方式：iOS/macOS=iCloud，Android=googleDrive，其它回退 iCloud。
  static BackupMethod cloudMethod() {
    if (Platform.isAndroid) return BackupMethod.googleDrive;
    return BackupMethod.iCloud;
  }

  /// 云备份副标题：说明备份到哪个平台服务。
  static String cloudSubtitle() => '备份到 ${cloudServiceName()}，更换设备可快速恢复';
}
