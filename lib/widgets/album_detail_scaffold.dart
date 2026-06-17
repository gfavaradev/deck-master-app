import 'package:flutter/material.dart';
import '../pages/card_list_page.dart';
import '../theme/app_colors.dart';
import 'album_app_bar_title.dart';

/// Scaffold for an album's card list: AppBar shows the album name and its
/// total value (kept in sync as CardListPage reports it), with no extra
/// banners duplicating that info in the body.
class AlbumDetailScaffold extends StatefulWidget {
  final String albumName;
  final int albumId;
  final String collectionName;
  final String collectionKey;

  const AlbumDetailScaffold({
    super.key,
    required this.albumName,
    required this.albumId,
    required this.collectionName,
    required this.collectionKey,
  });

  @override
  State<AlbumDetailScaffold> createState() => _AlbumDetailScaffoldState();
}

class _AlbumDetailScaffoldState extends State<AlbumDetailScaffold> {
  double _totalValue = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AlbumAppBarTitle(albumName: widget.albumName, totalValue: _totalValue),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: CardListPage(
        collectionName: widget.collectionName,
        collectionKey: widget.collectionKey,
        albumId: widget.albumId,
        onAlbumValueChanged: (value) {
          if (mounted) setState(() => _totalValue = value);
        },
      ),
    );
  }
}
