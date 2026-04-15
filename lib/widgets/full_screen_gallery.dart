import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';

/// Gallery a schermo intero con swipe orizzontale tra immagini.
/// Supporta pinch-to-zoom per carta: quando zoomata il PageView è disabilitato.
/// [onCardTap]: se fornito, dopo aver chiuso la gallery viene chiamato con
/// l'indice corrente (es. per aprire il dettaglio carta dal catalogo).
class FullScreenGallery extends StatefulWidget {
  final List<String?> imageUrls;
  final List<String> names;
  final int initialIndex;
  final ValueChanged<int>? onCardTap;

  const FullScreenGallery({
    super.key,
    required this.imageUrls,
    required this.names,
    required this.initialIndex,
    this.onCardTap,
  });

  @override
  State<FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<FullScreenGallery> {
  late PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;

  // Un TransformationController per pagina, per zoom indipendente
  final Map<int, TransformationController> _transformControllers = {};

  TransformationController _controllerFor(int index) {
    return _transformControllers.putIfAbsent(index, () {
      final c = TransformationController();
      c.addListener(() {
        final zoomed = c.value.getMaxScaleOnAxis() > 1.01;
        if (zoomed != _isZoomed && mounted) setState(() => _isZoomed = zoomed);
      });
      return c;
    });
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _transformControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onPageChanged(int index) {
    // Reset zoom sulla pagina che si lascia
    _transformControllers[_currentIndex]?.value = Matrix4.identity();
    setState(() {
      _currentIndex = index;
      _isZoomed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _currentIndex < widget.names.length
        ? widget.names[_currentIndex]
        : '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // PageView: disabilitato quando zoomato per non cambiare pagina per sbaglio
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: widget.imageUrls.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final imageUrl = widget.imageUrls[index];
              final tc = _controllerFor(index);
              return GestureDetector(
                onTap: () {
                  if (!_isZoomed) {
                    Navigator.pop(context);
                    widget.onCardTap?.call(_currentIndex);
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 80),
                    child: InteractiveViewer(
                      transformationController: tc,
                      minScale: 1,
                      maxScale: 5,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: imageUrl != null && imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.contain,
                                placeholder: (_, _) => const SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                        color: AppColors.gold),
                                  ),
                                ),
                                errorWidget: (_, _, _) => const Icon(
                                  Icons.broken_image,
                                  color: Colors.white,
                                  size: 64,
                                ),
                              )
                            : const SizedBox(
                                height: 200,
                                child: Center(
                                  child: Icon(Icons.style,
                                      color: Colors.white54, size: 64),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Contatore in alto al centro
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.imageUrls.length}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),

          // Tasto chiudi in alto a destra
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style:
                    IconButton.styleFrom(backgroundColor: Colors.black45),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Nome carta in basso
          if (name.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  color: Colors.black54,
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
