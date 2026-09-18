from pathlib import Path


PROJECT_DIR = Path(__file__).parents[1]


def test_installer_creates_missing_cache_before_changing_permissions():
    installer = (PROJECT_DIR / "install.sh").read_text()

    assert 'if [[ ! -e "$PROJECT_DIR/stock_prices.json" ]]' in installer
    assert 'install -o "$TARGET_USER" -g daemon -m 664 /dev/null' in installer


def test_uninstaller_only_removes_owned_project_environment():
    uninstaller = (PROJECT_DIR / "uninstall.sh").read_text()

    assert 'VENV_DIR="$PROJECT_DIR/.venv"' in uninstaller
    assert 'if [[ -f "$VENV_MARKER" ]]' in uninstaller


def test_service_disables_project_bytecode_creation():
    installer = (PROJECT_DIR / "install.sh").read_text()

    assert "Environment=PYTHONDONTWRITEBYTECODE=1" in installer


def test_uninstaller_removes_generated_bytecode_caches():
    uninstaller = (PROJECT_DIR / "uninstall.sh").read_text()

    assert "-name '__pycache__'" in uninstaller
