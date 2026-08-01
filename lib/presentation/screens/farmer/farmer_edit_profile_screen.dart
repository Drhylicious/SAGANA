import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/sagana_colors.dart';
import '../../../data/repositories/farmer_profile_repository.dart';
import '../../../data/services/profile_state_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/change_password_dialog.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/shared_widgets.dart';

/// Farmer Edit Profile — name, phone, sitio, photo, Change Password.
/// Route: /farmer/profile/edit. Mirrors AdminEditProfileScreen exactly;
/// replaces the bottom-sheet edit form and photo picker that previously
/// lived inline in FarmerProfileScreen/FarmerSettingsScreen.
class FarmerEditProfileScreen extends StatefulWidget {
  const FarmerEditProfileScreen({super.key});

  @override
  State<FarmerEditProfileScreen> createState() => _FarmerEditProfileScreenState();
}

class _FarmerEditProfileScreenState extends State<FarmerEditProfileScreen> {
  final _repo = FarmerProfileRepository();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  String? _photoUrl;
  String? _selectedSitio;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _repo.fetchProfile();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile?.fullName ?? '';
      _phoneController.text = profile?.phoneNumber ?? '';
      _photoUrl = profile?.profilePhotoUrl;
      _selectedSitio = profile?.sitio;
      _isLoading = false;
    });
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    final Uint8List bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last;
    final url = await _repo.uploadProfilePhoto(imageBytes: bytes, fileExtension: ext);
    if (!mounted) return;
    setState(() {
      _isUploadingPhoto = false;
      if (url != null) _photoUrl = url;
    });
    if (url != null) {
      FarmerProfileStateService.instance.refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload photo. Please try again.')),
      );
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Full name is required.'), backgroundColor: AppConstants.errorRed),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _repo.updateBasicInfo(
        fullName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        sitio: _selectedSitio,
      );
      FarmerProfileStateService.instance.refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.'), backgroundColor: AppConstants.successGreen),
      );
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save changes. Try again.'), backgroundColor: AppConstants.errorRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sagana = context.saganaColors;

    return Scaffold(
      backgroundColor: sagana.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: sagana.scaffoldBackground,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop(), color: AppConstants.primaryGreen),
        title: Text('Edit Profile',
            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text('Save',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: AppConstants.primaryGreen)),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppConstants.spacingSafeH, 16, AppConstants.spacingSafeH, 40),
              children: [
                Center(
                  child: Stack(
                    children: [
                      ProfileAvatar(
                        photoUrl: _photoUrl,
                        displayName: _nameController.text.isNotEmpty ? _nameController.text : 'Farmer',
                        radius: 56,
                      ),
                      if (_isUploadingPhoto)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                            child: const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          ),
                        )
                      else
                        Positioned(
                          bottom: 0, right: 0,
                          child: GestureDetector(
                            onTap: _pickPhoto,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: AppConstants.primaryGreen, shape: BoxShape.circle),
                              child: const Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _isUploadingPhoto ? null : _pickPhoto,
                    child: Text('Change Photo',
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppConstants.primaryGreen)),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel(label: 'Personal Information'),
                const SizedBox(height: 8),
                AppTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  prefixIcon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: AppConstants.payanasSitios.contains(_selectedSitio) ? _selectedSitio : null,
                  decoration: const InputDecoration(
                    labelText: 'Sitio / Purok',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 20, color: AppConstants.outline),
                  ),
                  items: AppConstants.payanasSitios.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _selectedSitio = v),
                ),
                const SizedBox(height: 24),
                const SectionLabel(label: 'Security'),
                const SizedBox(height: 8),
                SettingsCard(children: [
                  SettingsRow(
                    icon: Icons.lock_reset_rounded,
                    iconColor: AppConstants.primaryGreen,
                    title: 'Change Password',
                    subtitle: 'Update your account password',
                    onTap: () => AppDialog.show<void>(context: context, child: const ChangePasswordDialog()),
                  ),
                ]),
              ],
            ),
    );
  }
}