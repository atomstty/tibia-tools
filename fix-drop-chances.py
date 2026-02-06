#!/usr/bin/env python3
"""
fix-drop-chances.py - Analyze and fix monster drop chances

This script parses .mon files to find item drop rates and can update
drop chances to meet a minimum threshold.

The Inventory format in .mon files is:
    Inventory = {(item_id, count, chance), ...}

Where chance is out of 1000 (e.g., 10 = 1%, 100 = 10%, 1000 = 100%).
"""

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Drop:
    """Represents an item drop from a monster."""

    item_id: int
    count: int
    chance: int
    monster: str
    monster_path: Path


@dataclass
class ItemInfo:
    """Item information from objects.srv."""

    id: int
    name: str


def load_item_names(objects_srv_path: Path) -> dict[int, str]:
    """
    Parse objects.srv to build item_id -> name mapping.

    Format:
        TypeID      = 3031
        Name        = "a gold coin"
    """
    items = {}

    if not objects_srv_path.exists():
        return items

    content = objects_srv_path.read_text()

    # Match TypeID followed by Name on the next line(s)
    pattern = r'TypeID\s*=\s*(\d+)\s*(?:#[^\n]*)?\n(?:.*\n)*?Name\s*=\s*"([^"]*)"'

    for match in re.finditer(pattern, content):
        type_id = int(match.group(1))
        name = match.group(2)
        if name:  # Skip empty names
            items[type_id] = name

    return items


def parse_monster_file(filepath: Path) -> list[Drop]:
    """
    Parse a monster file and extract all inventory drops.

    Returns list of Drop objects.
    """
    drops = []
    content = filepath.read_text()
    monster_name = filepath.stem

    # Find the Inventory section
    inventory_match = re.search(r"Inventory\s*=\s*\{([^}]*)\}", content, re.DOTALL)
    if not inventory_match:
        return drops

    inventory_content = inventory_match.group(1)

    # Find all inventory entries: (item_id, count, chance)
    entry_pattern = r"\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)"

    for match in re.finditer(entry_pattern, inventory_content):
        item_id = int(match.group(1))
        count = int(match.group(2))
        chance = int(match.group(3))

        drops.append(
            Drop(
                item_id=item_id,
                count=count,
                chance=chance,
                monster=monster_name,
                monster_path=filepath,
            )
        )

    return drops


def load_all_drops(mon_dir: Path) -> list[Drop]:
    """Load all drops from all monster files."""
    all_drops = []

    for filepath in sorted(mon_dir.glob("*.mon")):
        drops = parse_monster_file(filepath)
        all_drops.extend(drops)

    return all_drops


def format_chance(chance: int) -> str:
    """Format chance as percentage string."""
    return f"{chance / 10:.1f}%"


def analyze_drops(
    drops: list[Drop],
    item_names: dict[int, str],
    top: int | None = None,
    below: int | None = None,
) -> list[int]:
    """
    Analyze and display drops grouped by item, sorted by rarest.

    Returns list of item IDs that match the filter (for --fix).
    """
    # Filter drops if --below specified
    if below is not None:
        drops = [d for d in drops if d.chance < below]

    if not drops:
        print("No drops found matching the criteria.")
        return []

    # Group drops by item
    by_item: dict[int, list[Drop]] = defaultdict(list)
    for drop in drops:
        by_item[drop.item_id].append(drop)

    # Sort items by their minimum (rarest) drop chance
    sorted_items = sorted(by_item.items(), key=lambda x: min(d.chance for d in x[1]))

    # Limit to top N items if specified
    if top is not None:
        sorted_items = sorted_items[:top]

    # Display results
    threshold_str = f"below {below}/1000 = {format_chance(below)}" if below else "all"
    print(f"Rarest item drops ({threshold_str}):\n")

    total_drops = 0
    monsters_with_drops = set()
    matched_item_ids = []

    for item_id, item_drops in sorted_items:
        item_name = item_names.get(item_id, f"item {item_id}")
        matched_item_ids.append(item_id)

        print(f"{item_name} ({item_id}) - {len(item_drops)} drop(s)")

        # Sort drops by chance (rarest first)
        item_drops_sorted = sorted(item_drops, key=lambda d: d.chance)

        for drop in item_drops_sorted:
            print(f"  {format_chance(drop.chance):>6}  {drop.monster}")
            total_drops += 1
            monsters_with_drops.add(drop.monster)

        print()

    # Summary
    print(
        f"Summary: {len(sorted_items)} unique items with {total_drops} drops {threshold_str} across {len(monsters_with_drops)} monsters"
    )

    return matched_item_ids


def fix_drops_in_file(
    filepath: Path,
    item_ids: set[int],
    min_chance: int,
    item_names: dict[int, str],
    dry_run: bool,
) -> list[tuple[int, int, int]]:
    """
    Fix drop chances in a single monster file.

    Returns list of changes: (item_id, old_chance, new_chance)
    """
    content = filepath.read_text()
    changes = []

    # Find the Inventory section
    inventory_pattern = r"(Inventory\s*=\s*\{)([^}]*)\}"

    def replace_inventory(match):
        prefix = match.group(1)
        inventory_content = match.group(2)

        entry_pattern = r"\((\d+)\s*,\s*(\d+)\s*,\s*(\d+)\)"

        def replace_entry(entry_match):
            item_id = int(entry_match.group(1))
            count = int(entry_match.group(2))
            chance = int(entry_match.group(3))

            # Only fix if item is in our target list and chance is below minimum
            if item_id in item_ids and chance < min_chance:
                changes.append((item_id, chance, min_chance))
                return f"({item_id}, {count}, {min_chance})"
            return entry_match.group(0)

        new_inventory = re.sub(entry_pattern, replace_entry, inventory_content)
        return prefix + new_inventory + "}"

    new_content = re.sub(inventory_pattern, replace_inventory, content, flags=re.DOTALL)

    if changes and not dry_run:
        filepath.write_text(new_content)

    return changes


def fix_drops(
    mon_dir: Path,
    item_ids: set[int],
    min_chance: int,
    item_names: dict[int, str],
    dry_run: bool,
) -> None:
    """Fix drop chances for specified items across all monster files."""
    prefix = "[DRY RUN] " if dry_run else ""

    print(
        f"\n{prefix}Fixing drops to minimum {min_chance}/1000 ({format_chance(min_chance)}):\n"
    )

    total_changes = 0
    files_modified = 0

    for filepath in sorted(mon_dir.glob("*.mon")):
        changes = fix_drops_in_file(filepath, item_ids, min_chance, item_names, dry_run)

        if changes:
            files_modified += 1
            print(f"  {filepath.name}:")

            for item_id, old_chance, new_chance in changes:
                item_name = item_names.get(item_id, f"item {item_id}")
                print(
                    f"    {item_name} ({item_id}): {old_chance} -> {new_chance} ({format_chance(old_chance)} -> {format_chance(new_chance)})"
                )
                total_changes += 1

    if total_changes == 0:
        print("  No changes needed.")
    else:
        action = "Would modify" if dry_run else "Modified"
        print(f"\n{action} {total_changes} drop(s) in {files_modified} file(s)")


def print_suggested_commands(item_ids: list[int], below: int | None) -> None:
    """Print suggested fix commands."""
    if not item_ids:
        return

    print("\nTo fix these items, run:")
    ids_str = " ".join(str(id) for id in item_ids[:20])
    if len(item_ids) > 20:
        ids_str += " ..."
    print(f"  ./fix-drop-chances.sh --fix {ids_str}")

    if below is not None:
        print("\nOr add --fix to this command:")
        print(f"  ./fix-drop-chances.sh --analyze --below {below} --fix")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze and fix monster drop chances.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  Analyze rarest drops (top 20):
    ./fix-drop-chances.sh --analyze

  Analyze items below 0.5%% drop rate:
    ./fix-drop-chances.sh --analyze --below 5

  Analyze and fix items below 0.5%%:
    ./fix-drop-chances.sh --analyze --below 5 --fix

  Fix specific items:
    ./fix-drop-chances.sh --fix 3366 3002 3574

  Fix all items below 1%% (preview):
    ./fix-drop-chances.sh --fix --all --dry-run
""",
    )

    # Path arguments (provided by bash wrapper)
    parser.add_argument(
        "--mon-dir", type=Path, required=True, help="Path to monster files directory"
    )
    parser.add_argument(
        "--objects-srv",
        type=Path,
        required=True,
        help="Path to objects.srv for item names",
    )

    # Commands
    parser.add_argument(
        "--analyze", action="store_true", help="Analyze and show rarest drops"
    )
    parser.add_argument(
        "--fix",
        nargs="*",
        type=int,
        metavar="ID",
        help="Fix drop chances for specific item IDs (or use with --all/--below)",
    )

    # Options for --analyze
    parser.add_argument(
        "--top", type=int, default=20, help="Show top N items (default: 20)"
    )
    parser.add_argument(
        "--below", type=int, help="Filter items below N/1000 chance (e.g., 10 = 1%%)"
    )

    # Options for --fix
    parser.add_argument(
        "--all", action="store_true", help="Fix all items below --min-chance threshold"
    )
    parser.add_argument(
        "--min-chance",
        type=int,
        default=10,
        help="Minimum chance to set (default: 10 = 1%%)",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Preview changes without applying"
    )

    args = parser.parse_args()

    # Show help if no command specified
    if not args.analyze and args.fix is None:
        parser.print_help()
        sys.exit(0)

    # Validate paths
    if not args.mon_dir.exists():
        print(f"Error: Monster directory not found: {args.mon_dir}", file=sys.stderr)
        sys.exit(1)

    # Load item names
    item_names = load_item_names(args.objects_srv)
    if not item_names:
        print(
            f"Warning: Could not load item names from {args.objects_srv}",
            file=sys.stderr,
        )

    # Load all drops
    all_drops = load_all_drops(args.mon_dir)
    if not all_drops:
        print("No drops found in monster files.", file=sys.stderr)
        sys.exit(1)

    # Determine which items to fix
    fix_item_ids: set[int] = set()

    if args.analyze:
        # Run analysis
        matched_ids = analyze_drops(
            all_drops,
            item_names,
            top=args.top if not args.fix else None,  # No limit if fixing
            below=args.below,
        )

        if args.fix is not None:
            # --analyze --fix: fix all items from analysis
            fix_item_ids = set(matched_ids)
        else:
            # Just analysis, print suggested commands
            print_suggested_commands(matched_ids, args.below)

    elif args.fix is not None:
        # --fix without --analyze
        if args.fix:
            # Specific item IDs provided
            fix_item_ids = set(args.fix)
        elif args.all:
            # --fix --all: fix all items below min_chance
            fix_item_ids = set(
                d.item_id for d in all_drops if d.chance < args.min_chance
            )
        elif args.below:
            # --fix --below N: fix all items below N
            fix_item_ids = set(d.item_id for d in all_drops if d.chance < args.below)
        else:
            print("Error: --fix requires item IDs, --all, or --below", file=sys.stderr)
            sys.exit(1)

    # Apply fixes if we have items to fix
    if fix_item_ids:
        fix_drops(args.mon_dir, fix_item_ids, args.min_chance, item_names, args.dry_run)


if __name__ == "__main__":
    main()
