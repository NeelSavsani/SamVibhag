import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _imagePicker = ImagePicker();

  XFile? _avatar;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  CountryCode _selectedCountry = const CountryCode(
    name: 'India',
    dialCode: '+91',
    flag: '🇮🇳',
  );

  CurrencyOption _selectedCurrency = const CurrencyOption(
    name: 'US Dollar',
    code: 'USD',
    symbol: r'$',
  );

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
    CurrencyOption(
      name: 'United Arab Emirates Dirham',
      code: 'AED',
      symbol: 'د.إ',
    ),
    CurrencyOption(name: 'Indian Rupee', code: 'INR', symbol: '₹'),
    CurrencyOption(name: 'Euro', code: 'EUR', symbol: '€'),
    CurrencyOption(name: 'British Pound', code: 'GBP', symbol: '£'),
    CurrencyOption(name: 'Canadian Dollar', code: 'CAD', symbol: r'$'),
    CurrencyOption(name: 'Australian Dollar', code: 'AUD', symbol: r'$'),
  ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final pickedImage = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 78,
      maxWidth: 900,
    );

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
            leading: Text(country.flag, style: const TextStyle(fontSize: 24)),
            title: Text(country.name),
            trailing: Text(
              country.dialCode,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            onTap: () => Navigator.pop(context, country),
          );
        },
      ),
    );

    if (selected != null) {
      setState(() => _selectedCountry = selected);
    }
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
        searchText: (currency) =>
            '${currency.name} ${currency.code} ${currency.symbol}',
        itemBuilder: (context, currency) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary.withValues(alpha: .12),
              child: Text(
                currency.symbol,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            title: Text(currency.name),
            subtitle: Text(currency.code),
            onTap: () => Navigator.pop(context, currency),
          );
        },
      ),
    );

    if (selected != null) {
      setState(() => _selectedCurrency = selected);
    }
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final fullName = _fullNameController.text.trim();
      final email = _emailController.text.trim();
      final phone = _phoneController.text.trim();

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );

      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-created',
          message: 'Account was not created. Please try again.',
        );
      }

      await user.updateDisplayName(fullName);

      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'fullName': fullName,
        'email': email,
        'phoneNumber': '${_selectedCountry.dialCode}$phone',
        'countryCode': _selectedCountry.dialCode,
        'countryName': _selectedCountry.name,
        'currencyName': _selectedCurrency.name,
        'currencyCode': _selectedCurrency.code,
        'currencySymbol': _selectedCurrency.symbol,
        'avatarLocalPath': _avatar?.path,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created successfully.')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (error) {
      _showError(_authErrorMessage(error));
    } catch (error) {
      _showError('Registration failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.warning,
        content: Text(message),
      ),
    );
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return error.message ?? 'Registration failed. Please try again.';
    }
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
                ? const [
                    Color(0xFF07111F),
                    Color(0xFF0F172A),
                    Color(0xFF172554),
                  ]
                : const [
                    Color(0xFFEFF6FF),
                    Color(0xFFFFFBF7),
                    Color(0xFFDBEAFE),
                  ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
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
                          'Create your account',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Set up your profile and default currency for smarter expense sharing.',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .65,
                            ),
                            height: 1.45,
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
                                  backgroundColor: AppTheme.primary.withValues(
                                    alpha: .14,
                                  ),
                                  backgroundImage: _avatar == null
                                      ? null
                                      : FileImage(File(_avatar!.path)),
                                  child: _avatar == null
                                      ? const Icon(
                                          Icons.person_rounded,
                                          size: 52,
                                          color: AppTheme.primary,
                                        )
                                      : null,
                                ),
                                Container(
                                  height: 34,
                                  width: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.scaffoldBackgroundColor,
                                      width: 3,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.photo_camera_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
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
                            if (value == null || value.trim().length < 2) {
                              return 'Enter your full name.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _InputField(
                          controller: _emailController,
                          label: 'Email address',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(email)) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _InputField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline_rounded,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').length < 6) {
                              return 'Password must be at least 6 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _InputField(
                          controller: _confirmPasswordController,
                          label: 'Confirm password',
                          icon: Icons.lock_reset_rounded,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.next,
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                          validator: (value) {
                            if (value != _passwordController.text) {
                              return 'Passwords do not match.';
                            }
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
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 20,
                                      ),
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
                                  if (!RegExp(r'^\d{10}$').hasMatch(phone)) {
                                    return 'Enter 10 digits.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _CurrencyTile(
                          currency: _selectedCurrency,
                          onChange: _selectCurrency,
                        ),
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: AppTheme.primary
                                  .withValues(alpha: .55),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Register',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
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
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: .14),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primary.withValues(alpha: .12),
            child: Text(
              currency.symbol,
              style: const TextStyle(
                color: AppTheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'I use ',
                children: [
                  TextSpan(
                    text: '${currency.code} (${currency.symbol})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const TextSpan(text: ' as my currency.'),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: const Text(
              'Change >>',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.maxLength,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final int? maxLength;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      maxLength: maxLength,
      validator: validator,
      decoration: _fieldDecoration(
        context,
        label,
        icon: icon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

InputDecoration _fieldDecoration(
  BuildContext context,
  String label, {
  IconData? icon,
  Widget? suffixIcon,
}) {
  final theme = Theme.of(context);

  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon),
    suffixIcon: suffixIcon,
    counterText: '',
    filled: true,
    fillColor: theme.cardColor.withValues(alpha: .86),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: theme.colorScheme.outline.withValues(alpha: .12),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppTheme.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppTheme.warning),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: AppTheme.warning, width: 1.4),
    ),
  );
}

class _SearchablePicker<T> extends StatefulWidget {
  const _SearchablePicker({
    required this.title,
    required this.items,
    required this.searchHint,
    required this.searchText,
    required this.itemBuilder,
  });

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final normalizedQuery = query.trim().toLowerCase();

    setState(() {
      _filteredItems = widget.items.where((item) {
        return widget.searchText(item).toLowerCase().contains(normalizedQuery);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: _filter,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _filteredItems.isEmpty
                    ? const Center(child: Text('No results found.'))
                    : ListView.separated(
                        itemCount: _filteredItems.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          return widget.itemBuilder(
                            context,
                            _filteredItems[index],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CountryCode {
  const CountryCode({
    required this.name,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String dialCode;
  final String flag;
}

class CurrencyOption {
  const CurrencyOption({
    required this.name,
    required this.code,
    required this.symbol,
  });

  final String name;
  final String code;
  final String symbol;
}
