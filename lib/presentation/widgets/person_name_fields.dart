import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/utils/person_name.dart';
import 'account_form_widgets.dart';
import 'app_dropdown_field.dart';
import 'auth_visuals.dart';
import 'shared_widgets.dart' show AppTextField;

/// Which form the name fields sit in. [auth] is the sign-up look (floating
/// labels, icons); [form] is the Manager's Create Farmer / Create Officer look
/// (a small label above each field); [profile] is the Edit Profile look, the
/// same fields as the phone and email beside them (AppTextField).
enum PersonNameFieldsStyle { auth, form, profile }

/// Surname and First Name (both required) on their own rows, then Middle
/// Initial and Suffix (both optional) side by side, then a live preview of the
/// complete name in the one format used everywhere: `First M. Surname Suffix`.
///
/// Used wherever a person enters or edits their name: sign-up, the Manager's
/// Create Farmer Member and Create Officer forms, every Edit Profile screen and
/// the Pending Applicant details. There is never a separate Full Name field.
/// Validation is inline and mirrors the database; the database rebuilds the full
/// name from the parts.
///
/// An account created before the name was split has no parts. For it, pass
/// [legacyFullName] and [allowAllBlank]: a note shows the name as it is stored,
/// and leaving every field empty keeps that name unchanged. Filling them in
/// (completing the profile) requires the usual surname and first name.
class PersonNameFields extends StatelessWidget {
  const PersonNameFields({
    super.key,
    required this.surnameController,
    required this.firstNameController,
    required this.middleInitialController,
    required this.suffix,
    required this.onSuffixChanged,
    this.style = PersonNameFieldsStyle.auth,
    this.allowAllBlank = false,
    this.legacyFullName,
  });

  final TextEditingController surnameController;
  final TextEditingController firstNameController;
  final TextEditingController middleInitialController;

  /// The chosen suffix, one of [PersonName.suffixes], or null for none.
  final String? suffix;
  final ValueChanged<String?> onSuffixChanged;
  final PersonNameFieldsStyle style;

  /// Nothing is required while every field is empty (and no suffix is chosen).
  final bool allowAllBlank;

  /// The stored one-line name of an account that has no parts yet.
  final String? legacyFullName;

  static const _noSuffix = 'none';

  bool get _allBlank =>
      allowAllBlank &&
      suffix == null &&
      PersonName.clean(surnameController.text).isEmpty &&
      PersonName.clean(firstNameController.text).isEmpty &&
      middleInitialController.text.trim().isEmpty;

  String? _partError(
    AppLocalizations l10n,
    String? value, {
    required bool isSurname,
  }) {
    if (_allBlank) return null;
    switch (PersonName.checkPart(value, required: true)) {
      case null:
        return null;
      case NamePartProblem.required:
        return isSurname
            ? l10n.nameSurnameRequired
            : l10n.nameFirstNameRequired;
      case NamePartProblem.length:
        return l10n.nameLengthError;
      case NamePartProblem.characters:
        return l10n.nameCharactersError;
    }
  }

  String? _initialError(AppLocalizations l10n, String? value) =>
      PersonName.isValidInitial(value) ? null : l10n.nameInitialError;

  Widget _legacyNotice(BuildContext context, AppLocalizations l10n) {
    final name = legacyFullName?.trim() ?? '';
    if (name.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(
        l10n.nameLegacyNotice(name),
        key: const ValueKey('name-legacy-notice'),
        style: GoogleFonts.inter(
          fontSize: 11,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // Letters, spaces, hyphens, apostrophes and periods only, as they are typed.
  List<TextInputFormatter> get _partFormatters => [
    FilteringTextInputFormatter.allow(PersonName.allowedChar),
    LengthLimitingTextInputFormatter(PersonName.maxPartLength),
  ];

  // One letter, optionally followed by a period.
  List<TextInputFormatter> get _initialFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÀ-ɏ.]')),
    LengthLimitingTextInputFormatter(2),
  ];

  Widget _preview(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([
        surnameController,
        firstNameController,
        middleInitialController,
      ]),
      builder: (context, _) {
        final surname = PersonName.clean(surnameController.text);
        final first = PersonName.clean(firstNameController.text);
        if (surname.isEmpty || first.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(
            l10n.nameFullNamePreview(
              PersonName.compose(
                firstName: first,
                middleInitial: middleInitialController.text,
                surname: surname,
                suffix: suffix,
              ),
            ),
            key: const ValueKey('name-preview'),
            style: GoogleFonts.inter(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (style) {
      case PersonNameFieldsStyle.auth:
        return _buildAuth(context, l10n);
      case PersonNameFieldsStyle.form:
        return _buildForm(context, l10n);
      case PersonNameFieldsStyle.profile:
        return _buildProfile(context, l10n);
    }
  }

  // ── Sign-up look ────────────────────────────────────────────────────────────

  Widget _buildAuth(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('name-surname'),
          controller: surnameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: _partFormatters,
          decoration: authFieldDecoration(
            label: '${l10n.nameSurnameLabel} *',
            hint: l10n.nameSurnameHint,
            icon: Icons.person_outlined,
          ).copyWith(errorMaxLines: 3),
          validator: (v) => _partError(l10n, v, isSurname: true),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('name-first'),
          controller: firstNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: _partFormatters,
          decoration: authFieldDecoration(
            label: '${l10n.nameFirstNameLabel} *',
            hint: l10n.nameFirstNameHint,
            icon: Icons.person_outlined,
          ).copyWith(errorMaxLines: 3),
          validator: (v) => _partError(l10n, v, isSurname: false),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('name-middle'),
                controller: middleInitialController,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                inputFormatters: _initialFormatters,
                // No leading icon here: two fields share the row.
                decoration: authFieldDecoration(
                  label: l10n.nameMiddleInitialLabel,
                ).copyWith(errorMaxLines: 3),
                validator: (v) => _initialError(l10n, v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // The app's standard dropdown (AppDropdownField), like Gender on
              // this same screen: label above, bordered field with the arrow
              // cell, and the list with dividers. "None" is the placeholder and
              // also the first choice, so a chosen suffix can be cleared.
              child: AppDropdownField<String>(
                key: const ValueKey('name-suffix'),
                value: suffix,
                hintText: l10n.nameSuffixNone,
                labelText: l10n.nameSuffixLabel,
                items: const [_noSuffix, ...PersonName.suffixes],
                // All seven choices fit without scrolling.
                menuMaxHeight: 340,
                itemLabel: (v) => v == _noSuffix ? l10n.nameSuffixNone : v,
                onChanged: (v) => onSuffixChanged(v == _noSuffix ? null : v),
              ),
            ),
          ],
        ),
        _preview(context, l10n),
        _legacyNotice(context, l10n),
      ],
    );
  }

  // ── Edit Profile look ───────────────────────────────────────────────────────

  Widget _buildProfile(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppTextField(
                key: const ValueKey('name-surname'),
                controller: surnameController,
                label: '${l10n.nameSurnameLabel} *',
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                inputFormatters: _partFormatters,
                validator: (v) => _partError(l10n, v, isSurname: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                key: const ValueKey('name-first'),
                controller: firstNameController,
                label: '${l10n.nameFirstNameLabel} *',
                prefixIcon: Icons.person_outline_rounded,
                textCapitalization: TextCapitalization.words,
                inputFormatters: _partFormatters,
                validator: (v) => _partError(l10n, v, isSurname: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          // Suffix has its label above the box (like Gender), M.I. has it inside:
          // the bottoms line up.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AppTextField(
                key: const ValueKey('name-middle'),
                controller: middleInitialController,
                label: l10n.nameMiddleInitialLabel,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: _initialFormatters,
                validator: (v) => _initialError(l10n, v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppDropdownField<String>(
                key: const ValueKey('name-suffix'),
                value: suffix,
                hintText: l10n.nameSuffixNone,
                labelText: l10n.nameSuffixLabel,
                items: const [_noSuffix, ...PersonName.suffixes],
                menuMaxHeight: 340,
                itemLabel: (v) => v == _noSuffix ? l10n.nameSuffixNone : v,
                onChanged: (v) => onSuffixChanged(v == _noSuffix ? null : v),
              ),
            ),
          ],
        ),
        _preview(context, l10n),
        _legacyNotice(context, l10n),
      ],
    );
  }

  // ── Manager form look ───────────────────────────────────────────────────────

  Widget _buildForm(BuildContext context, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccountFieldLabel(label: '${l10n.nameSurnameLabel} *', cs: cs),
        TextFormField(
          key: const ValueKey('name-surname'),
          controller: surnameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: _partFormatters,
          decoration: InputDecoration(
            hintText: l10n.nameSurnameHint,
            errorMaxLines: 3,
          ),
          validator: (v) => _partError(l10n, v, isSurname: true),
        ),
        const SizedBox(height: 14),
        AccountFieldLabel(label: '${l10n.nameFirstNameLabel} *', cs: cs),
        TextFormField(
          key: const ValueKey('name-first'),
          controller: firstNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          inputFormatters: _partFormatters,
          decoration: InputDecoration(
            hintText: l10n.nameFirstNameHint,
            errorMaxLines: 3,
          ),
          validator: (v) => _partError(l10n, v, isSurname: false),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AccountFieldLabel(label: l10n.nameMiddleInitialLabel, cs: cs),
                  TextFormField(
                    key: const ValueKey('name-middle'),
                    controller: middleInitialController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    inputFormatters: _initialFormatters,
                    decoration: const InputDecoration(errorMaxLines: 3),
                    validator: (v) => _initialError(l10n, v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AccountFieldLabel(label: l10n.nameSuffixLabel, cs: cs),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('name-suffix'),
                    initialValue: suffix ?? _noSuffix,
                    isExpanded: true,
                    decoration: const InputDecoration(errorMaxLines: 3),
                    items: [
                      for (final v in const [_noSuffix, ...PersonName.suffixes])
                        DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == _noSuffix ? l10n.nameSuffixNone : v,
                            style: GoogleFonts.inter(fontSize: 13),
                          ),
                        ),
                    ],
                    onChanged: (v) =>
                        onSuffixChanged(v == _noSuffix ? null : v),
                  ),
                ],
              ),
            ),
          ],
        ),
        _preview(context, l10n),
        _legacyNotice(context, l10n),
      ],
    );
  }
}

/// The state behind a [PersonNameFields] on a screen that edits a saved name:
/// the three text controllers and the chosen suffix, loaded from the account and
/// turned back into [NameParts] on save.
class PersonNameInput {
  final surname = TextEditingController();
  final firstName = TextEditingController();
  final middleInitial = TextEditingController();
  String? suffix;

  /// The stored one-line name when the account has no parts yet (created before
  /// the name was split). Null once the name is in parts.
  String? legacyFullName;

  /// Fills the fields from an account. Parts are shown as stored; an account
  /// without parts is NOT split (a wrong guess would be saved as its real name),
  /// so its fields stay empty and [legacyFullName] holds the one-line name.
  void load({
    required String? fullName,
    required String? surnameValue,
    required String? firstNameValue,
    String? middleInitialValue,
    String? suffixValue,
  }) {
    final parts = NameParts.fromRow({
      'surname': surnameValue,
      'first_name': firstNameValue,
      'middle_initial': middleInitialValue,
      'suffix': suffixValue,
    });
    if (parts != null) {
      surname.text = parts.surname;
      firstName.text = parts.firstName;
      middleInitial.text = parts.middleInitial ?? '';
      suffix = parts.suffix;
      legacyFullName = null;
    } else {
      surname.clear();
      firstName.clear();
      middleInitial.clear();
      suffix = null;
      final name = fullName?.trim() ?? '';
      legacyFullName = name.isEmpty ? null : name;
    }
  }

  /// Every field is empty (and no suffix). On an account without parts this
  /// means "leave my name as it is".
  bool get isBlank =>
      suffix == null &&
      PersonName.clean(surname.text).isEmpty &&
      PersonName.clean(firstName.text).isEmpty &&
      middleInitial.text.trim().isEmpty;

  /// The parts to save, or null when there is nothing to save (blank on an
  /// account that has no parts). Call after the form validated.
  NameParts? get parts => isBlank
      ? null
      : NameParts(
          surname: surname.text,
          firstName: firstName.text,
          middleInitial: middleInitial.text,
          suffix: suffix,
        );

  /// The complete name for display while editing (avatar initials), or
  /// [fallback] when nothing is entered.
  String displayName(String fallback) {
    final p = parts;
    if (p != null && p.surname.isNotEmpty && p.firstName.isNotEmpty) {
      return p.fullName;
    }
    return legacyFullName ?? fallback;
  }

  void dispose() {
    surname.dispose();
    firstName.dispose();
    middleInitial.dispose();
  }
}
