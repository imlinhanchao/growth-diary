import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../models/baby_event.dart';
import '../services/cloud_storage_service.dart';
import '../services/local_storage_service.dart';

class EventsSettingsScreen extends StatefulWidget {
  final AppConfig config;
  final CloudStorageService cloudService;
  final Function(AppConfig) onConfigChanged;

  const EventsSettingsScreen({
    super.key,
    required this.config,
    required this.cloudService,
    required this.onConfigChanged,
  });

  @override
  State<EventsSettingsScreen> createState() => _EventsSettingsScreenState();
}

class _EventsSettingsScreenState extends State<EventsSettingsScreen> {
  final LocalStorageService _localStorage = LocalStorageService();
  late AppConfig _config;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
  }

  Future<void> _saveConfig() async {
    await _localStorage.saveConfig(_config);
    await widget.cloudService.saveConfig(_config);
    widget.onConfigChanged(_config);
  }

  Future<void> _toggleEventVisibility(BabyEvent event) async {
    final updatedEvents = _config.events.map((e) {
      if (e.id == event.id) {
        return e.copyWith(isVisible: !e.isVisible);
      }
      return e;
    }).toList();
    setState(() {
      _config = _config.copyWith(events: updatedEvents);
    });
    await _saveConfig();
  }

  Future<void> _deleteEvent(BabyEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事件'),
        content: Text('确定要删除"${event.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final updatedEvents =
          _config.events.where((e) => e.id != event.id).toList();
      setState(() {
        _config = _config.copyWith(events: updatedEvents);
      });
      await _saveConfig();
    }
  }

  Future<void> _showAddOrEditEventDialog([BabyEvent? existingEvent]) async {
    String name = existingEvent?.name ?? '';
    final availableIcons = BabyEvent.availableIcons();
    int selectedIconCodePoint =
        existingEvent?.iconCodePoint ?? availableIcons.first['icon'].codePoint;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingEvent == null ? '添加事件' : '编辑事件'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  initialValue: name,
                  onChanged: (value) => name = value,
                  decoration: const InputDecoration(
                    labelText: '事件名称',
                    hintText: '请输入事件名称',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('选择图标', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      childAspectRatio: 1,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: availableIcons.length,
                    itemBuilder: (context, index) {
                      final item = availableIcons[index];
                      final iconData = item['icon'] as IconData;
                      final isSelected =
                          selectedIconCodePoint == iconData.codePoint;
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            selectedIconCodePoint = iconData.codePoint;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.pink.shade100
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: Colors.pink, width: 2)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                iconData,
                                color: isSelected
                                    ? Colors.pink
                                    : Colors.grey.shade600,
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['label'] as String,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isSelected
                                      ? Colors.pink
                                      : Colors.grey.shade600,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );

    if (result == true && name.isNotEmpty) {
      List<BabyEvent> updatedEvents;
      if (existingEvent == null) {
        updatedEvents = [
          ..._config.events,
          BabyEvent(name: name, iconCodePoint: selectedIconCodePoint),
        ];
      } else {
        updatedEvents = _config.events.map((e) {
          if (e.id == existingEvent.id) {
            return e.copyWith(name: name, iconCodePoint: selectedIconCodePoint);
          }
          return e;
        }).toList();
      }
      setState(() {
        _config = _config.copyWith(events: updatedEvents);
      });
      await _saveConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('事件管理',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddOrEditEventDialog(),
            tooltip: '添加事件',
          ),
        ],
      ),
      body: _config.events.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_note,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    '暂无事件，点击右上角添加',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
                  ),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _config.events.length,
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex--;
                final updatedEvents = List<BabyEvent>.from(_config.events);
                final item = updatedEvents.removeAt(oldIndex);
                updatedEvents.insert(newIndex, item);
                setState(() {
                  _config = _config.copyWith(events: updatedEvents);
                });
                await _saveConfig();
              },
              itemBuilder: (context, index) {
                final event = _config.events[index];
                return Card(
                  key: ValueKey(event.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: event.isVisible
                            ? Colors.pink.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        event.icon,
                        color: event.isVisible
                            ? Colors.pink.shade400
                            : Colors.grey.shade400,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      event.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color:
                            event.isVisible ? Colors.black87 : Colors.grey,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: event.isVisible,
                          onChanged: (_) => _toggleEventVisibility(event),
                          activeColor: Colors.pink,
                        ),
                        IconButton(
                          icon: Icon(Icons.edit,
                              size: 18, color: Colors.grey.shade500),
                          onPressed: () => _showAddOrEditEventDialog(event),
                          tooltip: '编辑',
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: Colors.red.shade300),
                          onPressed: () => _deleteEvent(event),
                          tooltip: '删除',
                        ),
                        const Icon(Icons.drag_handle, color: Colors.grey),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
