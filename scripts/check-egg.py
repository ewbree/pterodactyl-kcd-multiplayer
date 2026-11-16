#!/usr/bin/env python3
"""Check egg-kcd-mp.json against what Pterodactyl 1.x actually reads.

The contract is not a published schema, it is the code: EggParserService and
EggImporterService in pterodactyl/panel 1.0-develop, and EggVariable's columns.
This asserts the keys those read exist and have the shapes they expect, so a
typo fails here instead of as a half-imported egg on someone's panel.

Usage: scripts/check-egg.py [path/to/egg.json]
Exit code 0 when the egg is importable, 1 when it is not.
"""
import json
import re
import sys

# Environment variables the panel fills in itself, usable as {{...}} in startup.
CORE_VARS = {
    "SERVER_MEMORY", "SERVER_IP", "SERVER_PORT", "SERVER_MEMORY_OVERHEAD",
    "P_SERVER_LOCATION", "P_SERVER_UUID", "TZ", "STARTUP",
}

# EggVariable::RESERVED_ENV_NAMES (pterodactyl/panel 1.x). An egg variable
# using one of these fails validation on save, which the panel reports as a 500.
RESERVED_ENV_NAMES = {
    "SERVER_MEMORY", "SERVER_IP", "SERVER_PORT", "ENV", "HOME", "USER",
    "STARTUP", "SERVER_UUID", "UUID",
}

# Egg::$validationRules['docker_images.*'] in the panel, verbatim: the optional
# "label|" prefix followed by the image reference.
DOCKER_IMAGE_RE = re.compile(r"^[\w#\./\- ]*\|?~?[\w\./\-:@ ]*$")

# Egg::$validationRules['author'] is 'required|string|email'. Laravel's email
# rule is RFC-based; this is the stricter common form, which is all we need.
EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

problems = []
warnings = []


def need(obj, key, path, kind=None):
    if key not in obj:
        problems.append(f"{path}: missing '{key}'")
        return None
    value = obj[key]
    if kind is not None and not isinstance(value, kind):
        problems.append(f"{path}.{key}: expected {kind.__name__}, got {type(value).__name__}")
    return value


def main(path):
    with open(path, encoding="utf-8") as fh:
        egg = json.load(fh)

    meta = need(egg, "meta", "egg", dict) or {}
    version = need(meta, "version", "egg.meta")
    if version != "PTDL_v2":
        problems.append(f"egg.meta.version: expected PTDL_v2, got {version!r}")
    if "update_url" not in meta:
        warnings.append("egg.meta.update_url: absent (1.x tolerates it, exporters emit null)")

    for key in ("name", "author", "startup"):
        need(egg, key, "egg", str)
    name = egg.get("name", "")
    if not 1 <= len(name) <= 191:
        problems.append(f"egg.name: {len(name)} characters; the panel allows 1-191")
    author = egg.get("author", "")
    if isinstance(author, str) and not EMAIL_RE.match(author):
        problems.append(
            f"egg.author: {author!r} is not an email; the panel's egg model requires one "
            "(DataValidationException is returned as HTTP 500, not a field error)"
        )
    need(egg, "description", "egg", str)
    if "features" not in egg:
        problems.append("egg: missing 'features' (null is fine)")
    if "file_denylist" not in egg:
        problems.append("egg: missing 'file_denylist' (v2 field; [] is fine)")

    images = need(egg, "docker_images", "egg", dict) or {}
    if not images:
        problems.append("egg.docker_images: empty; the panel needs at least one image")
    for name, image in images.items():
        if not isinstance(image, str) or "/" not in image:
            problems.append(f"egg.docker_images[{name!r}]: expected a registry/repo:tag string")
            continue
        if len(image) > 191:
            problems.append(f"egg.docker_images[{name!r}]: {len(image)} characters; the panel allows 191")
        if not DOCKER_IMAGE_RE.match(image):
            problems.append(
                f"egg.docker_images[{name!r}]: {image!r} fails the panel's image regex "
                "(allowed: word characters, # . / - : @ and spaces, optional label| prefix)"
            )

    config = need(egg, "config", "egg", dict) or {}
    for key in ("files", "startup", "logs"):
        raw = need(config, key, "egg.config", str)
        if raw is not None:
            try:
                json.loads(raw)
            except json.JSONDecodeError as exc:
                problems.append(f"egg.config.{key}: not a JSON string: {exc}")
    stop = need(config, "stop", "egg.config", str)
    if isinstance(stop, str) and len(stop) > 191:
        problems.append(f"egg.config.stop: {len(stop)} characters; the panel allows 191")

    startup_json = config.get("startup", "{}")
    try:
        done = json.loads(startup_json).get("done", [])
    except json.JSONDecodeError:
        done = []
    if not done:
        warnings.append("egg.config.startup: no 'done' line; the panel will wait for a timestamp")
    for pattern in done:
        try:
            re.compile(pattern)
        except re.error as exc:
            problems.append(f"egg.config.startup.done: {pattern!r} does not compile: {exc}")

    scripts = (need(egg, "scripts", "egg", dict) or {}).get("installation", {})
    for key in ("script", "container", "entrypoint"):
        need(scripts, key, "egg.scripts.installation", str)

    variables = need(egg, "variables", "egg", list) or []
    seen = set()
    for i, var in enumerate(variables):
        where = f"egg.variables[{i}]"
        for key in ("name", "description", "env_variable", "default_value", "rules", "field_type"):
            need(var, key, where, str)
        for key in ("user_viewable", "user_editable"):
            need(var, key, where, bool)
        env = var.get("env_variable", "")
        if not re.fullmatch(r"[A-Z0-9_]+", env):
            problems.append(f"{where}.env_variable: {env!r} is not [A-Z0-9_]+")
        if len(env) > 191:
            problems.append(f"{where}.env_variable: {len(env)} characters; the panel allows 191")
        if env in RESERVED_ENV_NAMES:
            problems.append(
                f"{where}.env_variable: {env!r} is reserved by the panel "
                "(EggVariable::RESERVED_ENV_NAMES) and fails validation on save"
            )
        if env in seen:
            problems.append(f"{where}.env_variable: {env!r} is a duplicate")
        seen.add(env)
        var_name = var.get("name", "")
        if not 1 <= len(var_name) <= 191:
            problems.append(f"{where}.name: {len(var_name)} characters; the panel allows 1-191")
        field_type = var.get("field_type")
        if field_type not in ("text", "password", "select"):
            problems.append(f"{where}.field_type: {field_type!r} is not a 1.x type")
        if field_type == "select":
            # The panel builds the dropdown from the variable's in: rule, so a
            # select without one renders as an empty list.
            options = []
            for rule in str(var.get("rules", "")).split("|"):
                if rule.startswith("in:"):
                    options = [
                        option.strip().strip("\"'")
                        for option in rule[len("in:"):].split(",")
                        if option.strip()
                    ]
            if not options:
                problems.append(f"{where}: field_type is select but rules has no in: options")
            elif var.get("default_value") not in options:
                problems.append(
                    f"{where}.default_value: {var.get('default_value')!r} is not one of {options}"
                )

    # Every {{PLACEHOLDER}} in the startup command must resolve.
    for placeholder in set(re.findall(r"\{\{\s*([A-Z0-9_]+)\s*\}\}", egg.get("startup", ""))):
        if placeholder not in CORE_VARS and placeholder not in seen:
            problems.append(
                f"egg.startup: {{{{{placeholder}}}}} is neither a panel variable nor an egg variable"
            )

    for warning in warnings:
        print(f"warn:  {warning}")
    for problem in problems:
        print(f"error: {problem}")
    if problems:
        print(f"\n{len(problems)} problem(s): this egg will not import cleanly")
        return 1
    print(f"ok: {len(variables)} variables, {len(images)} image(s), schema PTDL_v2")
    return 0


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "egg/egg-kcd-mp.json"
    sys.exit(main(target))
