import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/upload_provider.dart';
import '../../providers/gallery_provider.dart';

/// 上传按钮组件
class UploadButton extends StatefulWidget {
  const UploadButton({Key? key}) : super(key: key);

  @override
  State<UploadButton> createState() => _UploadButtonState();
}

class _UploadButtonState extends State<UploadButton> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _handleUpload() async {
    // 选择图片
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 4096,
      maxHeight: 4096,
    );

    if (image == null || !mounted) return;

    // 上传
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uploadProvider = Provider.of<UploadProvider>(context, listen: false);
    final galleryProvider = Provider.of<GalleryProvider>(context, listen: false);

    if (authProvider.apiService == null) {
      _showMessage('服务未连接', isError: true);
      return;
    }

    // 显示加载提示
    _showMessage('正在上传...');

    final success = await uploadProvider.uploadFile(
      authProvider.apiService!,
      image.path,
      'uploads', // 默认上传到 uploads 文件夹
    );

    if (mounted) {
      if (success) {
        _showMessage('上传成功');
        // 刷新画廊
        await galleryProvider.refresh(authProvider.apiService!);
      } else {
        _showMessage('上传失败', isError: true);
      }
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicFloatingActionButton(
      onPressed: _handleUpload,
      style: NeumorphicStyle(
        depth: 6,
        intensity: 0.8,
        boxShape: const NeumorphicBoxShape.circle(),
        color: NeumorphicTheme.baseColor(context),
      ),
      child: const Icon(
        Icons.add_a_photo,
        size: 28,
        color: Color(0xFF171717),
      ),
    );
  }
}
