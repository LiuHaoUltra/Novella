import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:novella/core/logging/log_buffer_service.dart';
import 'package:novella/features/settings/widgets/log_card.dart';

/// 调试日志查看页面
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  Level? _filterLevel;
  final Set<String> _includedLoggers = {}; // 包含的模块
  final Set<String> _excludedLoggers = {}; // 排除的模块（反向选择）
  bool _moduleExpanded = false; // 模块列表是否展开
  bool _autoScroll = true; // 自动跟随最新日志
  String _searchQuery = ''; // 搜索关键字
  bool _isSearching = false; // 是否在搜索模式
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _refreshTimer;
  int _lastLogCount = 0;

  @override
  void initState() {
    super.initState();
    // 每秒自动刷新
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
        _scrollToBottomIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded() {
    if (_autoScroll && _scrollController.hasClients) {
      final logs = LogBufferService.getLogs();
      if (logs.length > _lastLogCount) {
        _lastLogCount = logs.length;
        // 使用 animateTo 平滑滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0, // reverse: true，所以0是底部
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 应用过滤规则
    var logs = LogBufferService.getLogs(minLevel: _filterLevel);

    // 按模块过滤
    if (_includedLoggers.isNotEmpty || _excludedLoggers.isNotEmpty) {
      logs =
          logs.where((log) {
            // 如果在排除列表中，过滤掉
            if (_excludedLoggers.contains(log.loggerName)) return false;
            // 如果有包含列表，只保留包含的
            if (_includedLoggers.isNotEmpty) {
              return _includedLoggers.contains(log.loggerName);
            }
            return true;
          }).toList();
    }

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      logs =
          logs.where((log) {
            final query = _searchQuery.toLowerCase();
            return log.message.toLowerCase().contains(query) ||
                log.loggerName.toLowerCase().contains(query);
          }).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title:
            _isSearching
                ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: '搜索日志...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                )
                : const Text('调试日志'),
        actions: [
          // 搜索按钮
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
              tooltip: '取消搜索',
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _isSearching = true),
              tooltip: '搜索',
            ),
          // 自动跟随按钮
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.arrow_downward : Icons.pause_circle_outline,
            ),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
            tooltip: _autoScroll ? '已开启自动跟随' : '已关闭自动跟随',
          ),
          // 清空日志按钮
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: () => _showClearDialog(),
            tooltip: '清空日志',
          ),
        ],
      ),
      body: Column(
        children: [
          // 过滤器栏
          _buildFilterBar(colorScheme),

          // 日志列表
          Expanded(
            child:
                logs.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                      onRefresh: () async {
                        setState(() {});
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: logs.length,
                        reverse: true, // 最新日志在下方
                        itemBuilder: (context, index) {
                          final entry = logs[logs.length - 1 - index];
                          return LogCard(
                            key: ValueKey(entry.time),
                            entry: entry,
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 级别过滤
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _filterLevel == null,
                  onSelected: (_) => setState(() => _filterLevel = null),
                  showCheckmark: false,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('错误'),
                  selected: _filterLevel == Level.SEVERE,
                  onSelected:
                      (_) => setState(() => _filterLevel = Level.SEVERE),
                  avatar: Icon(
                    Icons.error,
                    size: 18,
                    color:
                        _filterLevel == Level.SEVERE
                            ? Colors.white
                            : const Color(0xFFD32F2F),
                  ),
                  showCheckmark: false,
                  selectedColor: const Color(0xFFD32F2F),
                  labelStyle:
                      _filterLevel == Level.SEVERE
                          ? const TextStyle(color: Colors.white)
                          : null,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('警告'),
                  selected: _filterLevel == Level.WARNING,
                  onSelected:
                      (_) => setState(() => _filterLevel = Level.WARNING),
                  avatar: Icon(
                    Icons.warning_amber,
                    size: 18,
                    color:
                        _filterLevel == Level.WARNING
                            ? Colors.white
                            : const Color(0xFFF57C00),
                  ),
                  showCheckmark: false,
                  selectedColor: const Color(0xFFF57C00),
                  labelStyle:
                      _filterLevel == Level.WARNING
                          ? const TextStyle(color: Colors.white)
                          : null,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('信息'),
                  selected: _filterLevel == Level.INFO,
                  onSelected: (_) => setState(() => _filterLevel = Level.INFO),
                  avatar: Icon(
                    Icons.info,
                    size: 18,
                    color:
                        _filterLevel == Level.INFO
                            ? Colors.white
                            : const Color(0xFF1976D2),
                  ),
                  showCheckmark: false,
                  selectedColor: const Color(0xFF1976D2),
                  labelStyle:
                      _filterLevel == Level.INFO
                          ? const TextStyle(color: Colors.white)
                          : null,
                ),
              ],
            ),
          ),

          // 模块过滤
          const SizedBox(height: 8),
          Row(
            children: [
              // 所有模块按钮
              FilterChip(
                label: const Text('所有模块'),
                selected: _includedLoggers.isEmpty && _excludedLoggers.isEmpty,
                onSelected: (_) {
                  setState(() {
                    _includedLoggers.clear();
                    _excludedLoggers.clear();
                  });
                },
                showCheckmark: false,
              ),
              const Spacer(),
              // 展开/折叠按钮
              TextButton.icon(
                onPressed:
                    () => setState(() => _moduleExpanded = !_moduleExpanded),
                icon: Icon(
                  _moduleExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                ),
                label: Text(_moduleExpanded ? '收起' : '展开'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),

          // 展开的模块列表
          if (_moduleExpanded) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  LogBufferService.getLoggerNames().map((logger) {
                    final isIncluded = _includedLoggers.contains(logger);
                    final isExcluded = _excludedLoggers.contains(logger);

                    return GestureDetector(
                      onLongPress: () {
                        // 长按：反向选择（排除）
                        setState(() {
                          if (isExcluded) {
                            // 如果已是排除状态，取消排除（回到未选中）
                            _excludedLoggers.remove(logger);
                          } else {
                            // 否则，添加到排除（同时移除包含状态）
                            _includedLoggers.remove(logger);
                            _excludedLoggers.add(logger);
                          }
                        });
                      },
                      child: FilterChip(
                        label: Text(logger),
                        selected: isIncluded || isExcluded,
                        onSelected: (_) {
                          // 点击：包含选择
                          setState(() {
                            if (isIncluded) {
                              // 如果已是包含状态，取消包含
                              _includedLoggers.remove(logger);
                            } else {
                              // 否则，添加到包含（同时移除排除状态）
                              _excludedLoggers.remove(logger);
                              _includedLoggers.add(logger);
                            }
                          });
                        },
                        showCheckmark: false,
                        selectedColor:
                            isExcluded
                                ? Colors
                                    .red
                                    .shade700 // 排除状态：红色
                                : null, // 包含状态：默认主题色
                        labelStyle:
                            (isIncluded || isExcluded)
                                ? const TextStyle(color: Colors.white)
                                : null,
                      ),
                    );
                  }).toList(),
            ),
          ],

          // 统计信息
          const SizedBox(height: 8),
          Text(
            '共 ${LogBufferService.getLogs().length} 条日志'
            '${_includedLoggers.isNotEmpty ? ' (包含 ${_includedLoggers.length} 个模块)' : ''}'
            '${_excludedLoggers.isNotEmpty ? ' (排除 ${_excludedLoggers.length} 个模块)' : ''}',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无日志',
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '使用应用即可生成日志',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            icon: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
              size: 48,
            ),
            title: const Text('清空日志'),
            content: const Text('确认清空所有日志记录？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  LogBufferService.clear();
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('已清空所有日志')));
                },
                child: const Text('确定'),
              ),
            ],
          ),
    );
  }
}
