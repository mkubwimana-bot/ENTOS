import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/widgets/main_menu_nav_action.dart';

class _EditSupplierData {
  const _EditSupplierData({
    required this.partyId,
    required this.userId,
    required this.partyCode,
    required this.partyName,
    required this.phone,
    required this.status,
  });

  final String partyId;
  final String userId;
  final String partyCode;
  final String partyName;
  final String? phone;
  final String status;
}

final editSupplierProvider =
    FutureProvider.autoDispose.family<_EditSupplierData, String>((
  ref,
  partyId,
) async {
  final client = ref.read(supabaseClientProvider);
  final userId = client.auth.currentUser?.id;
  if (userId == null) throw Exception('You must be signed in.');

  final partyRows = await client
      .from('parties')
      .select('id, party_code, party_name, primary_phone, status')
      .eq('id', partyId)
      .isFilter('deleted_at', null)
      .limit(1);

  if ((partyRows as List).isEmpty) throw Exception('Supplier not found.');
  final party = partyRows.first as Map<String, dynamic>;

  return _EditSupplierData(
    partyId: party['id'] as String,
    userId: userId,
    partyCode: party['party_code'] as String? ?? '',
    partyName: party['party_name'] as String? ?? '',
    phone: party['primary_phone'] as String?,
    status: party['status'] as String? ?? 'active',
  );
});

class EditSupplierScreen extends ConsumerStatefulWidget {
  const EditSupplierScreen({required this.partyId, super.key});

  final String partyId;

  @override
  ConsumerState<EditSupplierScreen> createState() =>
      _EditSupplierScreenState();
}

class _EditSupplierScreenState extends ConsumerState<EditSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _status = 'active';
  bool _isSubmitting = false;
  bool _initialized = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _initFromData(_EditSupplierData data) {
    if (_initialized) return;
    _nameController.text = data.partyName;
    _phoneController.text = data.phone ?? '';
    _status = data.status;
    _initialized = true;
  }

  Future<void> _save(_EditSupplierData data) async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await ref.read(supabaseClientProvider).from('parties').update({
        'party_name': _nameController.text.trim(),
        'primary_phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'status': _status,
        'updated_by': data.userId,
      }).eq('id', data.partyId);

      if (mounted) Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not save supplier. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Enter supplier name';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final supplierAsync = ref.watch(editSupplierProvider(widget.partyId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Supplier'),
        actions: const [MainMenuNavAction()],
      ),
      body: supplierAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Could not load supplier: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.invalidate(editSupplierProvider(widget.partyId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          _initFromData(data);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue: data.partyCode,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Supplier code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Supplier name',
                        border: OutlineInputBorder(),
                      ),
                      validator: _validateName,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      enabled: !_isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                          value: 'inactive',
                          child: Text('Inactive'),
                        ),
                        DropdownMenuItem(
                          value: 'blocked',
                          child: Text('Blocked'),
                        ),
                      ],
                      onChanged: _isSubmitting
                          ? null
                          : (value) =>
                              setState(() => _status = value ?? 'active'),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style:
                            TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isSubmitting ? null : () => _save(data),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
