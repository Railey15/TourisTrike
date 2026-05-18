import 'package:flutter/material.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';

class SubTenantColors {
  static const background = Color(0xFFF6FAFF);
  static const backgroundAlt = Color(0xFFF4F8FF);
  static const card = Colors.white;
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const lightMuted = Color(0xFF94A3B8);
  static const blue = Color(0xFF2A86FF);
  static const deepBlue = Color(0xFF1E63E9);
  static const line = Color(0xFFE4ECF7);
  static const shadow = Color(0x12000000);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5DB4FF), Color(0xFF2A86FF), Color(0xFF1E63E9)],
  );
}

class SubTenantDashboardCard extends StatelessWidget {
  const SubTenantDashboardCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: SubTenantColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: const [
          BoxShadow(
            color: SubTenantColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SubTenantMetricCard extends StatelessWidget {
  const SubTenantMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.color = SubTenantColors.blue,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: SubTenantColors.text,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.lightMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SubTenantSectionHeader extends StatelessWidget {
  const SubTenantSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTrailingTap,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null)
          TextButton(
            onPressed: onTrailingTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              trailing!,
              style: const TextStyle(
                color: SubTenantColors.blue,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }
}

class SubTenantEmptyState extends StatelessWidget {
  const SubTenantEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: SubTenantColors.blue, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            SubTenantGradientButton(
              label: actionLabel!,
              icon: Icons.add_rounded,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}

class SubTenantGradientButton extends StatelessWidget {
  const SubTenantGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: SubTenantColors.gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: SubTenantColors.blue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon ?? Icons.check_rounded, color: Colors.white),
        label: Text(
          loading ? 'Saving...' : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class SubTenantSearchBar extends StatelessWidget {
  const SubTenantSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: SubTenantColors.lightMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: SubTenantColors.lightMuted,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
                icon: const Icon(
                  Icons.close_rounded,
                  color: SubTenantColors.lightMuted,
                ),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SubTenantColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SubTenantColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: SubTenantColors.blue, width: 1.2),
        ),
      ),
    );
  }
}

class SubTenantStatusPill extends StatelessWidget {
  const SubTenantStatusPill({super.key, required this.status, this.icon});

  final String status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = stStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, color: color, size: icon == null ? 8 : 13),
          const SizedBox(width: 6),
          Text(
            stTitleCase(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class SubTenantInfoTile extends StatelessWidget {
  const SubTenantInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: SubTenantColors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: SubTenantColors.blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: SubTenantColors.lightMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubTenantFilterChips extends StatelessWidget {
  const SubTenantFilterChips({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: values
            .map(
              (value) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ChipButton(
                  label: stTitleCase(value),
                  selected: selected == value,
                  onTap: () => onSelected(value),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? SubTenantColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? SubTenantColors.blue : SubTenantColors.line,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: SubTenantColors.blue.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : SubTenantColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class SubTenantTextField extends StatelessWidget {
  const SubTenantTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SubTenantColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          enabled: enabled,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: SubTenantColors.lightMuted,
              fontWeight: FontWeight.w600,
            ),
            filled: true,
            fillColor: enabled ? Colors.white : const Color(0xFFEFF5FC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: SubTenantColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: SubTenantColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: SubTenantColors.blue,
                width: 1.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SubTenantLoadingView extends StatelessWidget {
  const SubTenantLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class SubTenantErrorView extends StatelessWidget {
  const SubTenantErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SubTenantEmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Something went wrong',
          message: message,
          actionLabel: 'Retry',
          onAction: onRetry,
        ),
      ),
    );
  }
}

PreferredSizeWidget subTenantAppBar(
  BuildContext context, {
  required String title,
  bool showBack = false,
  List<Widget>? actions,
}) {
  return AppBar(
    elevation: 0,
    centerTitle: true,
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.white,
    leading: showBack
        ? IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: SubTenantColors.text,
              size: 18,
            ),
          )
        : null,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: SubTenantColors.text,
        fontSize: 17,
        fontWeight: FontWeight.w900,
      ),
    ),
    actions: actions,
  );
}

void showSubTenantSnack(
  BuildContext context,
  String message, {
  bool error = true,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFFDC2626)
            : const Color(0xFF16A34A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}
