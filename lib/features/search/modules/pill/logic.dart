// 搜索胶囊纯逻辑：与状态/UI 无关。

/// 首页搜索栏与搜索页输入框共享的 Hero 标签，用于「变形放大」过渡。
const String kSearchHeroTag = 'home-search-bar';

/// 关键词规整：去首尾空白并转小写，供各结果 Tab 统一匹配。
String normalizeQuery(String raw) => raw.trim().toLowerCase();
