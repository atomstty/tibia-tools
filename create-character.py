#!/usr/bin/env python3
"""
Create a new character by copying an existing one.

Creates a new account if it doesn't exist, or adds the character to an existing account.
Copies all character data (skills, inventory, spells, quests, etc.) from a source character.

Example usage:
    python3 create-character.py \\
        --account-id 5200766 \\
        --password bonus123 \\
        --character-name "Astromyst" \\
        --copy-from "Sir Aulan" \\
        --database data/querymanager/tibia.db \\
        --usr-dir data/game/usr
"""

import argparse
import hashlib
import os
import re
import sqlite3
import sys
from pathlib import Path


def generate_auth(password: str) -> bytes:
    """
    Generate 64-byte auth blob: SHA256(SHA256(password) XOR salt) + salt.
    Matches the scheme in tibia-querymanager/src/sha256.cc.
    """
    salt = os.urandom(32)
    hash1 = hashlib.sha256(password.encode()).digest()
    xored = bytes(a ^ b for a, b in zip(hash1, salt))
    final_hash = hashlib.sha256(xored).digest()
    return final_hash + salt


def get_usr_path(usr_dir: Path, character_id: int) -> Path:
    subdir = character_id % 100
    return usr_dir / f"{subdir:02d}" / f"{character_id}.usr"


def modify_usr_content(content: str, new_id: int, new_name: str) -> str:
    content = re.sub(
        r"^(ID\s*=\s*)\d+", rf"\g<1>{new_id}", content, count=1, flags=re.MULTILINE
    )

    content = re.sub(
        r'^(Name\s*=\s*)"[^"]*"',
        rf'\1"{new_name}"',
        content,
        count=1,
        flags=re.MULTILINE,
    )

    return content


def main():
    parser = argparse.ArgumentParser(
        description="Create a new character by copying an existing one.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    parser.add_argument(
        "--account-id",
        type=int,
        required=True,
        help="Account number for the new character",
    )
    parser.add_argument(
        "--password",
        type=str,
        default=None,
        help="Password for the account (required if account does not exist)",
    )
    parser.add_argument(
        "--character-name", type=str, required=True, help="Name for the new character"
    )
    parser.add_argument(
        "--copy-from",
        type=str,
        required=True,
        help="Name of the character to copy from",
    )
    parser.add_argument(
        "--database", type=Path, required=True, help="Path to tibia.db SQLite database"
    )
    parser.add_argument(
        "--usr-dir",
        type=Path,
        required=True,
        help="Path to usr directory containing character files",
    )
    parser.add_argument("--world-id", type=int, default=1, help="World ID (default: 1)")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )

    args = parser.parse_args()

    if not args.database.exists():
        print(f"Error: Database not found: {args.database}", file=sys.stderr)
        sys.exit(1)

    if not args.usr_dir.exists():
        print(f"Error: usr directory not found: {args.usr_dir}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(args.database)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    try:
        cursor.execute(
            "SELECT CharacterID, WorldID, AccountID, Name, Sex, Level, Profession, Residence "
            "FROM Characters WHERE Name = ? COLLATE NOCASE",
            (args.copy_from,),
        )
        source_char = cursor.fetchone()

        if not source_char:
            cursor.execute("SELECT Name FROM Characters ORDER BY Name LIMIT 20")
            available = [row["Name"] for row in cursor.fetchall()]
            print(
                f"Error: Source character '{args.copy_from}' not found.",
                file=sys.stderr,
            )
            print(
                f"Available characters (first 20): {', '.join(available)}",
                file=sys.stderr,
            )
            sys.exit(1)

        source_id = source_char["CharacterID"]
        print(f"Source character: {source_char['Name']} (ID: {source_id})")
        print(
            f"  Level {source_char['Level']} {source_char['Profession']}, {source_char['Residence']}"
        )

        cursor.execute(
            "SELECT CharacterID FROM Characters WHERE Name = ? COLLATE NOCASE",
            (args.character_name,),
        )
        if cursor.fetchone():
            print(
                f"Error: Character '{args.character_name}' already exists.",
                file=sys.stderr,
            )
            sys.exit(1)

        cursor.execute(
            "SELECT AccountID, Email FROM Accounts WHERE AccountID = ?",
            (args.account_id,),
        )
        account = cursor.fetchone()

        create_account = False
        if account:
            print(f"Account {args.account_id} exists (Email: {account['Email']})")
        else:
            if not args.password:
                print(
                    f"Error: Account {args.account_id} does not exist.", file=sys.stderr
                )
                print("Provide --password to create a new account.", file=sys.stderr)
                sys.exit(1)
            create_account = True
            print(f"Account {args.account_id} will be created")

        cursor.execute("SELECT MAX(CharacterID) as max_id FROM Characters")
        max_id_row = cursor.fetchone()
        new_id = (max_id_row["max_id"] or 0) + 1
        print(f"New character ID: {new_id}")

        source_usr_path = get_usr_path(args.usr_dir, source_id)
        dest_usr_path = get_usr_path(args.usr_dir, new_id)

        if not source_usr_path.exists():
            print(
                f"Error: Source .usr file not found: {source_usr_path}", file=sys.stderr
            )
            sys.exit(1)

        print(f"Source .usr file: {source_usr_path}")
        print(f"Destination .usr file: {dest_usr_path}")

        with open(source_usr_path, "r", encoding="latin-1") as f:
            source_content = f.read()

        new_content = modify_usr_content(source_content, new_id, args.character_name)

        if not re.search(rf"^ID\s*=\s*{new_id}\s*$", new_content, re.MULTILINE):
            print(
                "Warning: Could not verify ID was replaced correctly", file=sys.stderr
            )

        if args.character_name not in new_content:
            print(
                "Warning: Could not verify Name was replaced correctly", file=sys.stderr
            )

        print()
        print("=" * 60)
        print("SUMMARY")
        print("=" * 60)
        if create_account:
            print(f"  CREATE Account {args.account_id} with password '{args.password}'")
        print(f"  CREATE Character '{args.character_name}' (ID: {new_id})")
        print(f"    - Account: {args.account_id}")
        print(f"    - World: {args.world_id}")
        print(f"    - Copied from: {source_char['Name']}")
        print(f"    - Level: {source_char['Level']}")
        print(f"    - Profession: {source_char['Profession']}")
        print(f"    - Residence: {source_char['Residence']}")
        print(f"  WRITE {dest_usr_path}")
        print("=" * 60)

        if args.dry_run:
            print()
            print("DRY RUN - No changes made.")
            print()
            print("First 20 lines of modified .usr file:")
            print("-" * 40)
            for line in new_content.split("\n")[:20]:
                print(line)
            print("-" * 40)
            sys.exit(0)

        print()
        print("Executing...")

        if create_account:
            auth = generate_auth(args.password)
            email = f"@{args.account_id}"
            cursor.execute(
                "INSERT INTO Accounts (AccountID, Email, Auth) VALUES (?, ?, ?)",
                (args.account_id, email, auth),
            )
            print(f"  Created account {args.account_id}")

        cursor.execute(
            "INSERT INTO Characters "
            "(WorldID, CharacterID, AccountID, Name, Sex, Level, Profession, Residence) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                args.world_id,
                new_id,
                args.account_id,
                args.character_name,
                source_char["Sex"],
                source_char["Level"],
                source_char["Profession"],
                source_char["Residence"],
            ),
        )
        print(f"  Inserted character '{args.character_name}' into database")

        dest_usr_path.parent.mkdir(parents=True, exist_ok=True)

        with open(dest_usr_path, "w", encoding="latin-1") as f:
            f.write(new_content)
        print(f"  Wrote {dest_usr_path}")

        conn.commit()
        print()
        print("SUCCESS!")
        print()
        print(f"You can now login with:")
        print(f"  Account: {args.account_id}")
        if create_account:
            print(f"  Password: {args.password}")
        print(f"  Character: {args.character_name}")

    except Exception as e:
        conn.rollback()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
