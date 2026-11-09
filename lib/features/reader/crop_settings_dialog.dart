import 'package:flutter/material.dart';
import 'package:venera_next/foundation/image_crop.dart';

class ReaderCropDialog extends StatefulWidget {
  const ReaderCropDialog({super.key, required this.initial});
  final ReaderCrop initial;
  @override
  State<ReaderCropDialog> createState() => _ReaderCropDialogState();
}

class _ReaderCropDialogState extends State<ReaderCropDialog> {
  late String _mode = widget.initial.mode;
  late final _margins = [
    widget.initial.left,
    widget.initial.top,
    widget.initial.right,
    widget.initial.bottom,
  ];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('本漫画白边裁剪'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              isExpanded: true,
              value: _mode,
              items: const [
                DropdownMenuItem(value: 'off', child: Text('关闭，显示完整原图')),
                DropdownMenuItem(value: 'auto', child: Text('自动识别白边')),
                DropdownMenuItem(value: 'manual', child: Text('手动设置四边比例')),
              ],
              onChanged: (value) => setState(() => _mode = value!),
            ),
            if (_mode == 'manual')
              for (var i = 0; i < 4; i++) ...[
                Text(
                  '${const ['左', '上', '右', '下'][i]}：${(_margins[i] * 100).round()}%',
                ),
                Slider(
                  value: _margins[i],
                  max: .4,
                  divisions: 40,
                  onChanged: (value) => setState(() => _margins[i] = value),
                ),
              ],
            const Text(
              '对本漫画生效。原文件和下载不会修改，关闭即可恢复。已设遮罩的图片、超过 1600 万像素的长图及动图保留原图。',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          ReaderCrop(
            mode: _mode,
            left: _margins[0],
            top: _margins[1],
            right: _margins[2],
            bottom: _margins[3],
          ),
        ),
        child: const Text('应用'),
      ),
    ],
  );
}
