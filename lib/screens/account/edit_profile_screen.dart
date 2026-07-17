import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';

class CountryCode {
  const CountryCode({required this.name, required this.dialCode, required this.flag});
  final String name;
  final String dialCode;
  final String flag;
}

class CurrencyOption {
  const CurrencyOption({required this.name, required this.code, required this.symbol});
  final String name;
  final String code;
  final String symbol;
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  
  // Password Change Controllers
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _imagePicker = ImagePicker();

  XFile? _avatar;
  String _existingAvatarPath = '';
  bool _isLoading = true;
  bool _isUpdating = false;
  
  // Password Form Visibility Flags
  bool _showPasswordModule = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  CountryCode _selectedCountry = const CountryCode(name: 'India', dialCode: '+91', flag: '🇮🇳');
  CurrencyOption _selectedCurrency = const CurrencyOption(name: 'Indian Rupee', code: 'INR', symbol: '₹');
  
  // Timezone and Language State Settings
  String _selectedTimezone = 'Asia/Kolkata (GMT+5:30)';
  String _selectedLanguage = 'English (EN)';

  static const _countries = [
    CountryCode(name: 'India', dialCode: '+91', flag: '🇮🇳'),
    CountryCode(name: 'United States', dialCode: '+1', flag: '🇺🇸'),
    CountryCode(name: 'United Arab Emirates', dialCode: '+971', flag: '🇦🇪'),
    CountryCode(name: 'United Kingdom', dialCode: '+44', flag: '🇬🇧'),
    CountryCode(name: 'Canada', dialCode: '+1', flag: '🇨🇦'),
    CountryCode(name: 'Australia', dialCode: '+61', flag: '🇦🇺'),
    CountryCode(name: 'Singapore', dialCode: '+65', flag: '🇸🇬'),
  ];

  static const _currencies = [
    CurrencyOption(name: 'US Dollar', code: 'USD', symbol: r'$'),
    CurrencyOption(name: 'United Arab Emirates Dirham', code: 'AED', symbol: 'د.إ'),
    CurrencyOption(name: 'Indian Rupee', code: 'INR', symbol: '₹'),
    CurrencyOption(name: 'Euro', code: 'EUR', symbol: '€'),
    CurrencyOption(name: 'British Pound', code: 'GBP', symbol: '£'),
    CurrencyOption(name: 'Canadian Dollar', code: 'CAD', symbol: r'$'),
    CurrencyOption(name: 'Australian Dollar', code: 'AUD', symbol: r'$'),
  ];

  static const _timezones = [
    'Asia/Kolkata (GMT+5:30)',
    'London/Europe (GMT+0:00)',
    'New York/US (GMT-5:00)',
    'Los Angeles/US (GMT-8:00)',
    'Dubai/Asia (GMT+4:00)',
    'Singapore/Asia (GMT+8:00)',
    'Sydney/Australia (GMT+10:00)',
  ];

  static const _languages = [
    'English (EN)',
    'Hindi (HI)',
    'Gujarati (GU)',
    'Spanish (ES)',
    'French (FR)',
    'Arabic (AR)',
  ];

  @override
  void initState() {
    super.initState();
    _fetchUserProfileData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfileData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _fullNameController.text = data['fullName'] ?? user.displayName ?? '';
        
        String rawPhone = data['phoneNumber'] ?? '';
        String cCode = data['countryCode'] ?? '+91';
        if (rawPhone.startsWith(cCode)) {
          rawPhone = rawPhone.substring(cCode.length);
        }
        _phoneController.text = rawPhone;
        _existingAvatarPath = data['avatarLocalPath'] ?? '';
        _selectedTimezone = data['timezone'] ?? 'Asia/Kolkata (GMT+5:30)';
        _selectedLanguage = data['language'] ?? 'English (EN)';

        final matchedCountry = _countries.firstWhere(
          (c) => c.dialCode == data['countryCode'],
          orElse: () => _countries.first,
        );

        final matchedCurrency = _currencies.firstWhere(
          (c) => c.code == data['currencyCode'],
          orElse: () => _currencies.first,
        );

        setState(() {
          _selectedCountry = matchedCountry;
          _selectedCurrency = matchedCurrency;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Failed to fetch profile settings: $e', isError: true);
      }
    }
  }

  Future<void> _pickAvatar() async {
    final pickedImage = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 78, maxWidth: 900);
    if (pickedImage == null || !mounted) return;
    setState(() => _avatar = pickedImage);
  }

  Future<void> _selectCountryCode() async {
    final selected = await showModalBottomSheet<CountryCode>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchablePicker<CountryCode>(
        title: 'Choose country code',
        items: _countries,
        searchHint: 'Search country or code',
        searchText: (country) => '${country.name} ${country.dialCode}',
        itemBuilder: (context, country) => ListTile(
          leading: Text(country.flag, style: const TextStyle(fontSize: 22)),
          title: Text(country.name),
          trailing: Text(country.dialCode, style: const TextStyle(fontWeight: FontWeight.w800)),
          onTap: () => Navigator.pop(context, country),
        ),
      ),
    );
    if (selected != null) setState(() => _selectedCountry = selected);
  }

  Future<void> _selectCurrency() async {
    final selected = await showModalBottomSheet<CurrencyOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchablePicker<CurrencyOption>(
        title: 'Choose currency',
        items: _currencies,
        searchHint: 'Search currency or code',
        searchText: (currency) => '${currency.name} ${currency.code} ${currency.symbol}',
        itemBuilder: (context, currency) => ListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: .12),
            child: Text(currency.symbol, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900)),
          ),
          title: Text(currency.name),
          subtitle: Text(currency.code),
          onTap: () => Navigator.pop(context, currency),
        ),
      ),
    );
    if (selected != null) setState(() => _selectedCurrency = selected);
  }

  Future<void> _selectTimezone() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchablePicker<String>(
        title: 'Select Timezone',
        items: _timezones,
        searchHint: 'Search timezone...',
        searchText: (tz) => tz,
        itemBuilder: (context, tz) => ListTile(
          leading: const Icon(Icons.public_rounded, color: AppTheme.primary),
          title: Text(tz),
          trailing: _selectedTimezone == tz ? const Icon(Icons.check_circle, color: Color(0xFF00B074)) : null,
          onTap: () => Navigator.pop(context, tz),
        ),
      ),
    );
    if (selected != null) setState(() => _selectedTimezone = selected);
  }

  Future<void> _selectLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchablePicker<String>(
        title: 'Select Language',
        items: _languages,
        searchHint: 'Search language...',
        searchText: (lang) => lang,
        itemBuilder: (context, lang) => ListTile(
          leading: const Icon(Icons.translate_rounded, color: AppTheme.primary),
          title: Text(lang),
          trailing: _selectedLanguage == lang ? const Icon(Icons.check_circle, color: Color(0xFF00B074)) : null,
          onTap: () => Navigator.pop(context, lang),
        ),
      ),
    );
    if (selected != null) setState(() => _selectedLanguage = selected);
  }

  Future<void> _updateProfile() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // OPTIONAL PASSWORD MODIFICATION PIPELINE ROUTINE
      if (_showPasswordModule && _newPasswordController.text.isNotEmpty) {
        final email = user.email;
        if (email != null) {
          AuthCredential credential = EmailAuthProvider.credential(
            email: email,
            password: _currentPasswordController.text,
          );
          // Re-authenticate user security wrapper guardrail before letting password commit
          await user.reauthenticateWithCredential(credential);
          await user.updatePassword(_newPasswordController.text.trim());
        }
      }

      final fullName = _fullNameController.text.trim();
      final phone = _phoneController.text.trim();

      await user.updateDisplayName(fullName);

      await _firestore.collection('users').doc(user.uid).update({
        'fullName': fullName,
        'phoneNumber': '${_selectedCountry.dialCode}$phone',
        'countryCode': _selectedCountry.dialCode,
        'countryName': _selectedCountry.name,
        'currencyName': _selectedCurrency.name,
        'currencyCode': _selectedCurrency.code,
        'currencySymbol': _selectedCurrency.symbol,
        'timezone': _selectedTimezone,
        'language': _selectedLanguage,
        'avatarLocalPath': _avatar?.path ?? _existingAvatarPath,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showSnackBar('Profile configuration updated successfully.');
      setState(() => _isUpdating = false);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _isUpdating = false);
      _showSnackBar('Failed to save configurations: $error', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppTheme.warning : Colors.green,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF07111F), Color(0xFF0F172A), Color(0xFF172554)]
                : const [Color(0xFFEFF6FF), Color(0xFFFFFBF7), Color(0xFFDBEAFE)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : CustomScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverAppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      pinned: true,
                      leading: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.primary, size: 24),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 24, 28),
                      sliver: SliverToBoxAdapter(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit your profile',
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.5,
                                ),
                              ),
                              const SizedBox(height: 26),
                              Center(
                                child: GestureDetector(
                                  onTap: _pickAvatar,
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      CircleAvatar(
                                        radius: 50,
                                        backgroundColor: AppTheme.primary.withValues(alpha: .14),
                                        backgroundImage: _avatar != null
                                            ? FileImage(File(_avatar!.path))
                                            : (_existingAvatarPath.isNotEmpty
                                                ? FileImage(File(_existingAvatarPath)) as ImageProvider
                                                : null),
                                        child: _avatar == null && _existingAvatarPath.isEmpty
                                            ? const Icon(Icons.person_rounded, size: 52, color: AppTheme.primary)
                                            : null,
                                      ),
                                      Container(
                                        height: 34,
                                        width: 34,
                                        decoration: BoxDecoration(
                                          color: AppTheme.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: theme.scaffoldBackgroundColor, width: 3),
                                        ),
                                        child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              _InputField(
                                controller: _fullNameController,
                                label: 'Full name',
                                icon: Icons.person_outline_rounded,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().length < 2) return 'Enter your full name.';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 116,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: _selectCountryCode,
                                      child: InputDecorator(
                                        decoration: _fieldDecoration(context, 'Code'),
                                        child: Row(
                                          children: [
                                            Text(_selectedCountry.flag),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                _selectedCountry.dialCode,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _InputField(
                                      controller: _phoneController,
                                      label: 'Phone number',
                                      icon: Icons.phone_outlined,
                                      keyboardType: TextInputType.phone,
                                      maxLength: 10,
                                      textInputAction: TextInputAction.done,
                                      validator: (value) {
                                        final phone = value?.trim() ?? '';
                                        if (!RegExp(r'^\d{10}$').hasMatch(phone)) return 'Enter 10 digits.';
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _CurrencyTile(currency: _selectedCurrency, onChange: _selectCurrency),
                              
                              const SizedBox(height: 20),
                              const Text('Preferences', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),

                              // Timezone Selector Tile
                              ListTile(
                                leading: const Icon(Icons.access_time_filled_rounded, color: AppTheme.primary),
                                title: const Text('Timezone', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                subtitle: Text(_selectedTimezone, style: const TextStyle(fontWeight: FontWeight.bold)),
                                tileColor: theme.cardColor.withValues(alpha: .86),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: _selectTimezone,
                              ),
                              const SizedBox(height: 12),

                              // Language Selector Tile
                              ListTile(
                                leading: const Icon(Icons.language_rounded, color: AppTheme.primary),
                                title: const Text('App Language', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                subtitle: Text(_selectedLanguage, style: const TextStyle(fontWeight: FontWeight.bold)),
                                tileColor: theme.cardColor.withValues(alpha: .86),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                trailing: const Icon(Icons.chevron_right_rounded),
                                onTap: _selectLanguage,
                              ),

                              const SizedBox(height: 24),
                              
                              // PASSWORD RECOVERY EXPANDABLE ACTION BAR
                              Theme(
                                data: theme.copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                  iconColor: AppTheme.primary,
                                  initiallyExpanded: _showPasswordModule,
                                  onExpansionChanged: (value) => setState(() => _showPasswordModule = value),
                                  children: [
                                    const SizedBox(height: 8),
                                    _InputField(
                                      controller: _currentPasswordController,
                                      label: 'Current Password',
                                      icon: Icons.lock_open_rounded,
                                      obscureText: _obscureCurrent,
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscureCurrent ? Icons.visibility_off : Icons.visibility),
                                        onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                                      ),
                                      validator: (val) {
                                        if (_showPasswordModule && (val == null || val.isEmpty)) return 'Current password required.';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    _InputField(
                                      controller: _newPasswordController,
                                      label: 'New Password',
                                      icon: Icons.lock_outline_rounded,
                                      obscureText: _obscureNew,
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                                        onPressed: () => setState(() => _obscureNew = !_obscureNew),
                                      ),
                                      validator: (val) {
                                        if (_showPasswordModule && (val == null || val.length < 6)) return 'Password must be >= 6 characters.';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    _InputField(
                                      controller: _confirmPasswordController,
                                      label: 'Confirm New Password',
                                      icon: Icons.lock_reset_rounded,
                                      obscureText: _obscureConfirm,
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                                      ),
                                      validator: (val) {
                                        if (_showPasswordModule && val != _newPasswordController.text) return 'Passwords do not match.';
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 30),
                              SizedBox(
                                width: double.infinity,
                                height: 58,
                                child: ElevatedButton(
                                  onPressed: _isUpdating ? null : _updateProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: AppTheme.primary.withValues(alpha: .55),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  ),
                                  child: _isUpdating
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                                        )
                                      : const Text('Save Changes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({required this.currency, required this.onChange});
  final CurrencyOption currency;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: .14)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: .12),
            child: Text(currency.symbol, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'I use ',
                children: [
                  TextSpan(text: '${currency.code} (${currency.symbol})', style: const TextStyle(fontWeight: FontWeight.w900)),
                  const TextSpan(text: ' as my currency.'),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Change >>', style: TextStyle(fontWeight: FontWeight.w900))),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({required this.controller, required this.label, required this.icon, this.keyboardType, this.textInputAction, this.maxLength, this.validator, this.obscureText = false, this.suffixIcon});
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLength: maxLength,
      validator: validator,
      obscureText: obscureText,
      decoration: _fieldDecoration(context, label, icon: icon, suffixIcon: suffixIcon),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String label, {IconData? icon, Widget? suffixIcon}) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon),
    suffixIcon: suffixIcon,
    counterText: '',
    filled: true,
    fillColor: theme.cardColor.withValues(alpha: .86),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: theme.colorScheme.outline.withValues(alpha: .12))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppTheme.primary, width: 1.6)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppTheme.warning)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: AppTheme.warning, width: 1.4)),
  );
}

class _SearchablePicker<T> extends StatefulWidget {
  const _SearchablePicker({required this.title, required this.items, required this.searchHint, required this.searchText, required this.itemBuilder});
  final String title;
  final List<T> items;
  final String searchHint;
  final String Function(T item) searchText;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  State<_SearchablePicker<T>> createState() => _SearchablePickerState<T>();
}

class _SearchablePickerState<T> extends State<_SearchablePicker<T>> {
  final _searchController = TextEditingController();
  late List<T> _filteredItems = widget.items;

  void _filter(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    setState(() {
      _filteredItems = widget.items.where((item) => widget.searchText(item).toLowerCase().contains(normalizedQuery)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: _filter,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _filteredItems.isEmpty
                    ? const Center(child: Text('No results found.'))
                    : ListView.separated(
                        itemCount: _filteredItems.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => widget.itemBuilder(context, _filteredItems[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}