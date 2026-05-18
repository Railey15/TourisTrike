import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminPageContainer extends StatelessWidget {
  const AdminPageContainer({
    super.key,
    this.children,
    this.child,
    this.padding,
    this.controller,
  }) : assert(child != null || children != null);

  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      physics: AlwaysScrollableScrollPhysics(
        parent: Responsive.isMobile(context)
            ? const BouncingScrollPhysics()
            : const ClampingScrollPhysics(),
      ),
      padding:
          padding ??
          Responsive.responsiveValue<EdgeInsets>(
            context,
            mobile: const EdgeInsets.fromLTRB(16, 12, 16, 112),
            tablet: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            desktop: const EdgeInsets.fromLTRB(16, 24, 16, 34),
          ),
      children: [
        child ??
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children!,
            ),
      ],
    );
  }
}

class AdminResponsiveGrid extends StatelessWidget {
  const AdminResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.maxColumns = 4,
    this.spacing = 14,
    this.runSpacing = 14,
    this.mobileAspectRatio = 1.55,
    this.tabletAspectRatio = 1.35,
    this.desktopAspectRatio = 1.45,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;
  final double mobileAspectRatio;
  final double tabletAspectRatio;
  final double desktopAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = constraints.maxWidth ~/ minItemWidth;
        if (columns < 1) columns = 1;
        if (columns > maxColumns) columns = maxColumns;
        if (children.length < columns && children.isNotEmpty) {
          columns = children.length;
        }

        final aspectRatio = Responsive.responsiveValue<double>(
          context,
          mobile: mobileAspectRatio,
          tablet: tabletAspectRatio,
          desktop: desktopAspectRatio,
        );

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: runSpacing,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
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
                  color: ProvincialAdminColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: ProvincialAdminColors.muted,
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
                color: ProvincialAdminColors.blue,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }
}

class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
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
          color: ProvincialAdminColors.lightMuted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: ProvincialAdminColors.lightMuted,
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
                  color: ProvincialAdminColors.lightMuted,
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
          borderSide: const BorderSide(color: ProvincialAdminColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: ProvincialAdminColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: ProvincialAdminColors.blue,
            width: 1.2,
          ),
        ),
      ),
    );
  }
}

class AdminFilterChips extends StatelessWidget {
  const AdminFilterChips({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.labelBuilder,
  });

  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;
  final String Function(String value)? labelBuilder;

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
                  label: labelBuilder?.call(value) ?? value,
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
          color: selected ? ProvincialAdminColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? ProvincialAdminColors.blue
                : ProvincialAdminColors.line,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: ProvincialAdminColors.blue.withValues(alpha: 0.18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : ProvincialAdminColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class AdminLoadingView extends StatelessWidget {
  const AdminLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class AdminErrorView extends StatelessWidget {
  const AdminErrorView({
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
        child: AdminEmptyState(
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

class AdminInfoTile extends StatelessWidget {
  const AdminInfoTile({
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
                  color: ProvincialAdminColors.blue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: ProvincialAdminColors.blue, size: 22),
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
                        color: ProvincialAdminColors.text,
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
                        color: ProvincialAdminColors.muted,
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
                  color: ProvincialAdminColors.lightMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void showAdminSnack(
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
            ? ProvincialAdminColors.red
            : ProvincialAdminColors.green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}
