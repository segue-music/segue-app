import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../app/page_area.dart';
import '../widgets/arrow_scroll.dart';
import '../widgets/spinner.dart';

/// The licenses of the app and of what it is made with, as Flutter gathers them ([LicenseRegistry]): the app's own,
/// Flutter's, the Dart packages' and those of the libraries media_kit brings (lib/player/libmpv_licenses.dart). A
/// package a line, by name, with how many licenses it has; one picked opens them, a page of its own
/// ([PackageLicensesPage]). In the page area, from the settings, rather than Flutter's own page, which has a back arrow
/// even under a wide screen's top bar.
class LicensesPage extends StatefulWidget {
  const LicensesPage({super.key});

  @override
  State<LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<LicensesPage> {
  final _packages = _gather();

  /// Each package and its licenses, by the package's name, whatever its case. A license of several packages is in
  /// each of them.
  static Future<List<({String package, List<LicenseEntry> licenses})>> _gather() async {
    final licenses = <String, List<LicenseEntry>>{};

    await for (final license in LicenseRegistry.licenses) {
      for (final package in license.packages) {
        (licenses[package] ??= []).add(license);
      }
    }

    final packages = licenses.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [for (final package in packages) (package: package, licenses: licenses[package]!)];
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
        automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
        title: Text(strings.licenses),
      ),
      body: FutureBuilder(
        future: _packages,
        builder: (context, snapshot) {
          final packages = snapshot.data;

          if (packages == null) {
            return const Center(child: Spinner());
          }

          return ListView.builder(
            // At the end, clear of the bars a phone's home has over it.
            padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
            itemCount: packages.length,
            itemBuilder: (context, i) {
              final (:package, :licenses) = packages[i];
              return ListTile(
                title: Text(package),
                subtitle: Text(strings.licenseCount(licenses.length)),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => PackageLicensesPage(package, licenses))),
              );
            },
          );
        },
      ),
    );
  }
}

/// A package's licenses, one after the other, a line between them. Nothing in them takes the focus, so up and down (a
/// TV remote's, a keyboard's) scroll them, and only at their ends go on, to the bars around the page.
class PackageLicensesPage extends StatefulWidget {
  const PackageLicensesPage(this.package, this.licenses, {super.key});

  final String package;
  final List<LicenseEntry> licenses;

  @override
  State<PackageLicensesPage> createState() => _PackageLicensesPageState();
}

class _PackageLicensesPageState extends State<PackageLicensesPage> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      // Under a wide screen's top bar, whose arrow goes back: no arrow of its own.
      automaticallyImplyLeading: !PageArea.holdsUnderTopBar(context),
      title: Text(widget.package),
    ),
    body: ArrowScroll(
      controller: _scroll,
      child: ListView.separated(
        controller: _scroll,
        // At the end, clear of the bars a phone's home has over it.
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
        itemCount: widget.licenses.length,
        separatorBuilder: (_, _) => const Divider(height: 33),
        itemBuilder: (context, i) => _LicenseText(widget.licenses[i]),
      ),
    ),
  );
}

/// A license's paragraphs, as Flutter's own page shows them: those it centers (titles) in bold, the others indented
/// by their level.
class _LicenseText extends StatelessWidget {
  const _LicenseText(this.license);

  final LicenseEntry license;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final paragraph in license.paragraphs)
        if (paragraph.indent == LicenseParagraph.centeredIndent)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              paragraph.text,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          )
        else
          Padding(
            padding: EdgeInsetsDirectional.only(top: 8, start: 16.0 * paragraph.indent),
            child: Text(paragraph.text),
          ),
    ],
  );
}
