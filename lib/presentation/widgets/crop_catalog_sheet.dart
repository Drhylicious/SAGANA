import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/crop_repository.dart';
import 'app_dropdown_field.dart';
import 'management_modal.dart';
import 'material_list_tile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CropCatalogSheet
// Shown from My Crops. Farmer adds an existing crop from the Admin's
// official catalog, or requests one that isn't there yet.
//
// Rebuilt as a single ManagementModal with two internal steps (Browse /
// Request) instead of a sliding bottom sheet that launched a second,
// independent AlertDialog on top of it. Only one modal is ever on screen:
// tapping "Request New Crop" swaps the body in place; the header's title
// and subtitle change with it. "Cancel" and the in-body "Back to crop
// list" link both return to Browse rather than closing the whole flow —
// only the outer ✕ (or a successful add/request) closes it entirely.
// ─────────────────────────────────────────────────────────────────────────────

enum _CropCatalogStep { browse, request }

Future<bool?> showCropCatalogSheet(
  BuildContext context, {
  required CropRepository repo,
  required List<String> existingCropMasterIds,
}) {
  return showManagementModal<bool>(
    context: context,
    builder: (_) => _CropCatalogModal(
      repo: repo,
      existingCropMasterIds: existingCropMasterIds,
    ),
  );
}

class _CropCatalogModal extends StatefulWidget {
  final CropRepository repo;
  final List<String> existingCropMasterIds;

  const _CropCatalogModal({
    required this.repo,
    required this.existingCropMasterIds,
  });

  @override
  State<_CropCatalogModal> createState() => _CropCatalogModalState();
}

class _CropCatalogModalState extends State<_CropCatalogModal> {
  _CropCatalogStep _step = _CropCatalogStep.browse;
  final _categoryRepo = CategoryRepository();

  // ── Browse step state ──
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _catalog = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  String? _addingId; // tracks which tile is mid-submit, for a small inline spinner

  // ── Request step state ──
  final _nameController = TextEditingController();
  List<String> _categories = [];
  String? _category;
  String _cropType = 'open_market';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      widget.repo.fetchCropCatalog(),
      _categoryRepo.fetchCropCategories(),
    ]);
    if (!mounted) return;
    final catalog = results[0] as List<Map<String, dynamic>>;
    setState(() {
      _catalog = catalog
          .where((c) => !widget.existingCropMasterIds.contains(c['id'] as String))
          .toList();
      _filtered = _catalog;
      _categories = results[1] as List<String>;
      _isLoading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _catalog
          : _catalog
              .where((c) => (c['crop_name'] as String).toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _addFromCatalog(Map<String, dynamic> entry) async {
    setState(() => _addingId = entry['id'] as String);
    try {
      await widget.repo.addCrop(
        cropName: entry['crop_name'] as String,
        category: entry['category'] as String,
        cropMasterId: entry['id'] as String,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _addingId = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not add crop. Please try again.',
                style: GoogleFonts.inter(fontSize: 13)),
          ),
        );
      }
    }
  }

  void _goToRequestStep() => setState(() => _step = _CropCatalogStep.request);

  void _goBackToBrowse() => setState(() => _step = _CropCatalogStep.browse);

  Future<void> _submitRequest() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.repo.requestNewCrop(
        cropName: name,
        category: _category!,
        cropType: _cropType,
      );
      // The crop is usable immediately (per the copy below) — closing the
      // whole modal here, rather than bouncing back to Browse, since the
      // farmer's task ("add a crop") is done.
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit request. Please try again.',
                style: GoogleFonts.inter(fontSize: 13)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step == _CropCatalogStep.request) {
      return ManagementModalShell(
        title: 'Request New Crop',
        subtitle:
            "You can use this crop right away — SP3 will review and add it to the official list.",
        body: _buildRequestBody(),
        footer: _buildRequestFooter(context),
      );
    }
    return ManagementModalShell(
      title: 'Add a Crop to Grow',
      subtitle: "Choose from SP3's official crop list.",
      body: _buildBrowseBody(context),
    );
  }

  // ── Browse step ────────────────────────────────────────────────────────

  Widget _buildBrowseBody(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search crops',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            filled: true,
            fillColor: AppConstants.offWhite,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: AppConstants.primaryGreen),
            ),
          )
        else if (_filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              _catalog.isEmpty
                  ? "You've already added every crop in the catalog."
                  : 'No matches. Try a different search, or request a new crop below.',
              style: GoogleFonts.inter(fontSize: 13, color: AppConstants.onSurfaceVariant),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.36,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final entry = _filtered[i];
                final isAdding = _addingId == entry['id'];
                final imageUrl = entry['image_url'] as String?;
                return MaterialListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppConstants.primaryGreen.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? Image.network(imageUrl, fit: BoxFit.cover)
                        : const Icon(Icons.eco_rounded,
                            color: AppConstants.primaryGreen, size: 20),
                  ),
                  title: Text(entry['crop_name'] as String,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(entry['category'] as String,
                      style: GoogleFonts.inter(fontSize: 12, color: AppConstants.onSurfaceVariant)),
                  trailing: isAdding
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppConstants.primaryGreen),
                        )
                      : const Icon(Icons.add_circle_outline_rounded,
                          color: AppConstants.primaryGreen),
                  onTap: isAdding ? null : () => _addFromCatalog(entry),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        MaterialListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.help_outline_rounded, color: AppConstants.onSurfaceVariant),
          title: Text(
            "Can't find your crop?",
            style: GoogleFonts.poppins(
                fontSize: 13, fontWeight: FontWeight.w500, color: AppConstants.onSurfaceVariant),
          ),
          subtitle: Text(
            'Request New Crop',
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen),
          ),
          onTap: _goToRequestStep,
        ),
      ],
    );
  }

  // ── Request step ───────────────────────────────────────────────────────

  Widget _buildRequestBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _isSubmitting ? null : _goBackToBrowse,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_back_rounded, size: 16, color: AppConstants.primaryGreen),
              const SizedBox(width: 4),
              Text(
                'Back to crop list',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Crop name'),
        ),
        const SizedBox(height: 12),
        AppDropdownField<String>(
          value: _category,
          hintText: 'Select a category',
          labelText: 'Category',
          items: _categories,
          itemLabel: (c) => c,
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: 12),
        AppDropdownField<String>(
          value: _cropType,
          hintText: 'Select a market type',
          labelText: 'Market Type (SP3 will confirm)',
          items: const ['sp3_cooperative', 'open_market'],
          itemLabel: (v) => v == 'sp3_cooperative' ? 'Cooperative Market' : 'Public Market',
          onChanged: (v) => setState(() => _cropType = v ?? _cropType),
        ),
      ],
    );
  }

  Widget _buildRequestFooter(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.30)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
            onPressed: _isSubmitting ? null : _goBackToBrowse,
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: cs.onSurface),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _submitRequest,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Submit', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}