"""Refuse to run next to the upstream ``pyopia`` distribution.

pyopia-nst and the upstream PyOPIA distribution both install the ``pyopia``
import package, so they overwrite each other's files if installed into the same
environment. Metadata alone cannot stop pip or uv from installing both, so
this check runs at import time and fails loudly instead of mixing the two.
"""

from importlib import metadata


def check():
    try:
        metadata.distribution("pyopia")
    except metadata.PackageNotFoundError:
        return
    raise ImportError(
        "pyopia-nst and the upstream 'pyopia' distribution are both installed "
        "in this environment. They share the 'pyopia' import name and cannot "
        "coexist. Uninstall one of them (pip uninstall pyopia pyopia-nst) and "
        "reinstall the one you want."
    )


check()
