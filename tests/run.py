from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
subprocess.run(['node',str(ROOT/'tests/resale.cjs')],check=True)
