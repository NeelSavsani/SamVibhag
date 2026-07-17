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

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _imagePicker = ImagePicker();

  XFile? _avatar;
  String _existingAvatarPath = '';
  bool _isLoading = true;
  bool _isUpdating = false;

  CountryCode _selectedCountry = const CountryCode(name: 'India', dialCode: '+91', flag: '🇮🇳');
  CurrencyOption _selectedCurrency = const CurrencyOption(name: 'Indian Rupee', code: 'INR', symbol: '₹');

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

  @override
  void initState() {
    super.initState();
    _fetchUserProfileData();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Fetch pre-values from database using current user UID
  Future<void> _fetchUserProfileData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        _fullNameController.text = data['fullName'] ?? user.displayName ?? '';
        
        // Extract plain phone number by removing country dial code prefix if present
        String rawPhone = data['phoneNumber'] ?? '';
        String cCode = data['countryCode'] ?? '+91';
        if (rawPhone.startsWith(cCode)) {
          rawPhone = rawPhone.substring(cCode.length);
        }
        _phoneController.text = rawPhone;

        _existingAvatarPath = data['avatarLocalPath'] ?? '';

        // Match stored country metadata structure
        final matchedCountry = _countries.firstWhere(
          (c) => c.dialCode == data['countryCode'],
          orElse: () => _countries.first,
        );

        // Match stored currency metadata structure
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
        itemBuilder: (context, country) {
          return ListTile(
            leading: Text(country.flag, style: const TextStyle(fontSize: 22)),
            title: Text(country.name),
            trailing: Text(country.dialCode, style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () => Navigator.pop(context, country),
          );
        },
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
        itemBuilder: (context, currency) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: .12),
              child: Text(currency.symbol, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900)),
            ),
            title: Text(currency.name),
            subtitle: Text(currency.code),
            onTap: () => Navigator.pop(context, currency),
          );
        },
      ),
    );
    if (selected != null) setState(() => _selectedCurrency = selected);
  }

  Future<void> _updateProfile() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final fullName = _fullNameController.text.trim();
      final phone = _phoneController.text.trim();

      // 1. Update Auth Profile Display Name
      await user.updateDisplayName(fullName);

      // 2. Update Document parameters in Cloud Firestore
      await _firestore.collection('users').doc(user.uid).update({
        'fullName': fullName,
        'phoneNumber': '${_selectedCountry.dialCode}$phone',
        'countryCode': _selectedCountry.dialCode,
        'countryName': _selectedCountry.name,
        'currencyName': _selectedCurrency.name,
        'currencyCode': _selectedCurrency.code,
        'currencySymbol': _selectedCurrency.symbol,
        'avatarLocalPath': _avatar?.path ?? _existingAvatarPath,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      _showSnackBar('Profile configuration updated successfully.');
      setState(() => _isUpdating = false);
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _isUpdating = false);
      _showSnackBar('Failed to update details: $error', isError: true);
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
                              const SizedBox(height: 40),
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
  const _InputField({required this.controller, required this.label, required this.icon, this.keyboardType, this.textInputAction, this.maxLength, this.validator});
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLength;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      maxLength: maxLength,
      validator: validator,
      decoration: _fieldDecoration(context, label, icon: icon),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String label, {IconData? icon}) {
  final theme = Theme.of(context);
  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon),
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