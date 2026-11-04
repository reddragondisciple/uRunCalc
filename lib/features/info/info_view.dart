part of '../../main.dart';

class _InfoView extends StatelessWidget {
  const _InfoView();

  static const String _url = 'https://github.com/reddragondisciple/uRunCalc';

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(AppStrings.infoLinkCopied)));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 48,
              color: AppColors.result,
            ),
            const SizedBox(height: 16),
            const Text(
              AppStrings.appName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.infoTagline,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 28),
            const Text(
              AppStrings.infoAuthor,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 8),
            InkWell(
              key: const ValueKey('info-github-link'),
              onTap: () => _copyLink(context),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  _url,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64B5F6),
                    fontSize: 15,
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF64B5F6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              AppStrings.infoCopyHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// Рисует выражение как набор inline-виджетов с настоящими вертикальными дробями.
