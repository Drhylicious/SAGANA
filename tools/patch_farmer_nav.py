import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent / "lib" / "presentation" / "screens" / "farmer"

NAV_IMPORTS = """import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/navigation_utils.dart';
"""

def ensure_imports(text: str) -> str:
    if "navigation_utils.dart" in text:
        return text
    m = re.search(r"(import '[^']+';\n)(?![i])", text)
    if m:
        return text[: m.end()] + NAV_IMPORTS + text[m.end() :]
    return NAV_IMPORTS + text

def replace_nav(text: str) -> str:
    text = text.replace("Navigator.of(context).pushNamed(", "context.pushRoute(")
    text = text.replace("Navigator.of(context).pushReplacementNamed(", "context.goTab(")
    text = text.replace("Navigator.of(context).pop(", "context.popRoute(")
    text = text.replace("Navigator.pop(context)", "context.popRoute()")
    text = text.replace("Navigator.pop(ctx)", "context.popRoute()")
    text = re.sub(
        r"Navigator\.of\(context\)\.pushNamedAndRemoveUntil\(\s*AppRoutes\.login,\s*\(route\) => false,?\s*\);",
        "context.go(AppRoutes.login);",
        text,
    )
    text = re.sub(
        r"Navigator\.of\(context\)\s*\.pushNamedAndRemoveUntil\(\s*AppRoutes\.login,\s*\(route\) => false,\s*\);",
        "context.go(AppRoutes.login);",
        text,
    )
    return text

def remove_bottom_nav(text: str) -> str:
    text = re.sub(
        r"\n\s*bottomNavigationBar: _\w+BottomNav\([\s\S]*?\),\n(?=\s*\);)",
        "\n",
        text,
    )
    text = re.sub(
        r"\n// ─+\n// Bottom Navigation[\s\S]*$",
        "\n",
        text,
    )
    return text

def add_did_change_dependencies(text: str) -> str:
    if "didChangeDependencies" in text or "HarvestHubScreen" not in text:
        pass
    if "AppTheme.applySystemOverlay" in text:
        return text
    pattern = r"(void initState\(\) \{[\s\S]*?\n  \})"
    replacement = r"\1\n\n  @override\n  void didChangeDependencies() {\n    super.didChangeDependencies();\n    AppTheme.applySystemOverlay(context);\n  }"
    return re.sub(pattern, replacement, text, count=1)

for path in sorted(ROOT.glob("*.dart")):
    if path.name == "farmer_dashboard_screen.dart":
        continue
    original = path.read_text(encoding="utf-8")
    updated = original
    updated = ensure_imports(updated)
    updated = replace_nav(updated)
    updated = remove_bottom_nav(updated)
    if path.name != "farmer_settings_screen.dart":
        updated = add_did_change_dependencies(updated)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"updated {path.name}")
