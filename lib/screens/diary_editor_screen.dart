import 'package:flutter/material.dart';
import '../models/app_config.dart';
import '../services/entry_creation_service.dart';
import '../services/cloud_storage_service.dart';

class DiaryEditorScreen extends StatefulWidget {
  final AppConfig config;
  final CloudStorageService webdavService;

  const DiaryEditorScreen({
    super.key,
    required this.config,
    required this.webdavService,
  });

  @override
  State<DiaryEditorScreen> createState() => _DiaryEditorScreenState();
}

class _DiaryEditorScreenState extends State<DiaryEditorScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  late final EntryCreationService _entryService;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _entryService = EntryCreationService(widget.webdavService);
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveDiary() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少输入标题或内容')),
      );
      return;
    }

    try {
      var entry = await _entryService.createDiaryEntry(
          title, content, widget.config,
          customDate: _selectedDate);
      await widget.webdavService.saveDiaryEntry(entry);
      if (!mounted) return;
      Navigator.of(context).pop(); // 返回上一页
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存日记失败: $e')),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  String _getWeekday(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[date.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final displayDate = _selectedDate ?? DateTime.now();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '写日记',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: Colors.black87,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: TextButton(
              onPressed: _saveDiary,
              style: TextButton.styleFrom(
                backgroundColor: Colors.pink.shade50,
                foregroundColor: Colors.pink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('保存',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 日期选择条
          InkWell(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.calendar_today_rounded,
                        size: 18, color: Colors.pink),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDate(displayDate),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getWeekday(displayDate),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded,
                      size: 14, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),

          // 内容编辑区域
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题输入
                  TextField(
                    controller: _titleController,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                    decoration: const InputDecoration(
                      hintText: '输入标题...',
                      hintStyle: TextStyle(
                          color: Colors.grey, fontWeight: FontWeight.bold),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 内容输入
                  TextField(
                    controller: _contentController,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.6,
                      color: Colors.black87,
                    ),
                    decoration: const InputDecoration(
                      hintText: '记录今天发生的趣事...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    maxLines: null, // 自适应高度
                  ),
                  const SizedBox(height: 100), // 底部留白，防止被键盘遮挡
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
