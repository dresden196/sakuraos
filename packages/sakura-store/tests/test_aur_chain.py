"""aur_chain against a fake AUR: the shapes real packages rarely show at once.

Run: python3 -m unittest discover -s packages/sakura-store/tests
Nothing here touches the network or the package database.
"""
import importlib.util
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location(
    "transaction", Path(__file__).resolve().parent.parent / "transaction.py")
tx = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tx)


class FakeAur:
    """pkgname -> (pkgbase, deps, provides); repo is what pacman can install."""

    def __init__(self, pkgs, repo=(), installed=()):
        self.pkgs, self.repo, self.installed = pkgs, set(repo), set(installed)

    def info(self, names):
        out = {}
        for n in names:
            if n in self.pkgs:
                base, _, provides = self.pkgs[n]
                out[n] = {"Name": n, "PackageBase": base, "Version": "1-1",
                          "Provides": list(provides)}
        return out

    def provider(self, dep):
        for n, (_, _, provides) in self.pkgs.items():
            if dep in [tx._bare(p) for p in provides]:
                return self.info([n])[n]
        return {}

    def srcinfo(self, base, pkgname):
        return list(self.pkgs[pkgname][1])

    def classify(self, deps):
        unmet = [d for d in deps if d not in self.installed]
        return ({d for d in unmet if d in self.repo},
                [d for d in unmet if d not in self.repo])

    def __enter__(self):
        self.saved = (tx._aur_info, tx._aur_provider, tx._srcinfo_deps,
                      tx._classify, tx._kernel_headers)
        tx._aur_info, tx._aur_provider = self.info, self.provider
        tx._srcinfo_deps, tx._classify = self.srcinfo, self.classify
        tx._kernel_headers = lambda: ["linux-cachyos-headers"]
        return self

    def __exit__(self, *exc):
        (tx._aur_info, tx._aur_provider, tx._srcinfo_deps,
         tx._classify, tx._kernel_headers) = self.saved


class AurChain(unittest.TestCase):
    def test_single_package(self):
        with FakeAur({"app": ("app", ["glibc"], [])}, repo=["glibc"]):
            c = tx.aur_chain("app")
        self.assertEqual(c["order"], ["app"])
        self.assertEqual(c["repo"], ["glibc"])

    def test_dependencies_build_first_three_deep(self):
        with FakeAur({"app": ("app", ["lib1"], []),
                      "lib1": ("lib1", ["lib2", "zlib"], []),
                      "lib2": ("lib2", [], [])}, repo=["zlib"]):
            c = tx.aur_chain("app")
        self.assertEqual(c["order"], ["lib2", "lib1", "app"])
        self.assertEqual([p["needed_by"] for p in c["packages"]], ["", "app", "lib1"])

    def test_provided_name_finds_its_provider(self):
        with FakeAur({"displaylink": ("displaylink", ["evdi"], []),
                      "evdi-dkms": ("evdi-dkms", ["dkms"], ["evdi=1.15"])},
                     repo=["dkms", "linux-cachyos-headers"]):
            c = tx.aur_chain("displaylink")
        self.assertEqual(c["order"], ["evdi-dkms", "displaylink"])
        self.assertEqual(c["packages"][1]["provides_for"], "evdi")
        # DKMS without headers builds nothing.
        self.assertIn("linux-cachyos-headers", c["repo"])

    def test_shared_dependency_built_once(self):
        with FakeAur({"app": ("app", ["a", "b"], []),
                      "a": ("a", ["common"], []), "b": ("b", ["common"], []),
                      "common": ("common", [], [])}):
            c = tx.aur_chain("app")
        self.assertEqual(c["order"].count("common"), 1)
        self.assertLess(c["order"].index("common"), c["order"].index("a"))
        self.assertLess(c["order"].index("common"), c["order"].index("b"))
        self.assertEqual(c["order"][-1], "app")

    def test_provider_already_in_chain_is_not_added_twice(self):
        with FakeAur({"app": ("app", ["impl", "iface"], []),
                      "impl": ("impl", [], ["iface"])}):
            c = tx.aur_chain("app")
        self.assertEqual(c["order"], ["impl", "app"])

    def test_dependency_loop_terminates(self):
        with FakeAur({"a": ("a", ["b"], []), "b": ("b", ["a"], [])}):
            c = tx.aur_chain("a")
        self.assertEqual(sorted(c["order"]), ["a", "b"])
        self.assertEqual(c["order"][-1], "a")

    def test_split_package_builds_its_base_once(self):
        with FakeAur({"app": ("app", ["libfoo", "libfoo-extra"], []),
                      "libfoo": ("foo", [], []), "libfoo-extra": ("foo", [], [])}):
            c = tx.aur_chain("app")
        self.assertEqual(c["order"], ["foo", "app"])
        foo = next(p for p in c["packages"] if p["pkgbase"] == "foo")
        self.assertEqual(sorted(foo["pkgnames"]), ["libfoo", "libfoo-extra"])

    def test_nothing_supplies_it(self):
        with FakeAur({"app": ("app", ["gone"], [])}):
            c = tx.aur_chain("app")
        self.assertEqual(c["missing"], ["gone"])

    def test_already_installed_is_not_rebuilt(self):
        with FakeAur({"app": ("app", ["lib1"], []), "lib1": ("lib1", [], [])},
                     installed=["lib1"]):
            c = tx.aur_chain("app")
        self.assertEqual(c["order"], ["app"])

    def test_unknown_package(self):
        with FakeAur({}):
            c = tx.aur_chain("nope")
        self.assertTrue(c["error"].startswith("There is no AUR package called nope"))


if __name__ == "__main__":
    unittest.main()
