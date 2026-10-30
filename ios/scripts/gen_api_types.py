"""
ios/scripts/gen_api_types.py
============================
Generate the iOS app's Swift API types from ``openapi/v1.json``.

    .venv/bin/python ios/scripts/gen_api_types.py          # rewrite the Swift file
    .venv/bin/python ios/scripts/gen_api_types.py --check  # exit 1 when it is stale

The output is checked in (``APITypes.generated.swift``) so a reviewer sees
every contract change as a Swift diff, and the build needs no plugin.
``tests/test_ios_codegen.py`` fails when the spec changed and this was not
rerun.  The generator covers exactly the OpenAPI subset the contract uses
(objects with ``additionalProperties: false``, string enums, ``$ref``,
nullable via a type list or ``oneOf``/``anyOf`` with ``null``, arrays); it
raises on anything else, so a new construct can't silently decode wrong.

What it emits, all inside ``public enum API`` so names like ``Color`` never
collide with SwiftUI:

* one ``Codable`` struct per object schema, one ``String`` enum per string
  enum (a numeric enum stays its number type: the server validates it);
* ``Endpoints``: one factory per operation (``Endpoints.getOverview(filters:)``);
* ``API.responseTypes``: operationId to its 200 response type, which the
  fixture tests use to decode every recorded fixture.
"""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "openapi" / "v1.json"
OUT = (ROOT / "ios" / "ChessDashboardKit" / "Sources" / "ChessDashboardKit" / "API"
       / "APITypes.generated.swift")

# Schema names that would shadow a Swift standard type inside `API`.
RENAMES = {"Error": "ErrorResponse"}

SWIFT_KEYWORDS = {
    "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer",
    "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate",
    "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
    "nil", "operator", "private", "protocol", "public", "repeat", "rethrows", "return",
    "self", "Self", "static", "struct", "subscript", "super", "switch", "throw", "throws",
    "true", "try", "typealias", "var", "where", "while", "Type", "Any",
}

PRIMITIVES = {"string": "String", "integer": "Int", "number": "Double", "boolean": "Bool"}
FILTER_REF = "#/components/parameters/lens"


def camel(name: str) -> str:
    parts = [p for p in re.split(r"[^0-9A-Za-z]+", name) if p]
    if not parts:
        raise ValueError(f"cannot name {name!r}")
    out = parts[0][0].lower() + parts[0][1:] + "".join(p[0].upper() + p[1:] for p in parts[1:])
    if out[0].isdigit():
        out = "_" + out
    return f"`{out}`" if out in SWIFT_KEYWORDS else out


# Symbols that carry meaning in an enum value ("< −200", "≥ +200").
SYMBOL_WORDS = {"<": " below ", ">": " above ", "≤": " at most ", "≥": " at least ",
                "−": " minus ", "+": " plus "}


def case_name(value: str) -> str:
    """An enum case for a raw value, keeping symbols that tell values apart."""
    spelled = value
    for symbol, word in SYMBOL_WORDS.items():
        spelled = spelled.replace(symbol, word)
    spelled = re.sub(r"(?<![0-9A-Za-z])-(?=[0-9])", " minus ", spelled)
    return camel(spelled)


def pascal(name: str) -> str:
    bare = camel(name).strip("`").lstrip("_")
    return bare[0].upper() + bare[1:]


def type_name(schema_name: str) -> str:
    return RENAMES.get(schema_name, schema_name)


def doc(text: str | None, indent: str) -> list[str]:
    if not text:
        return []
    return [f"{indent}/// {line}".rstrip() for line in text.strip().splitlines()]


def swift_string(value: str) -> str:
    escaped = (value.replace("\\", "\\\\").replace('"', '\\"')
               .replace("\n", "\\n").replace("\t", "\\t"))
    return f'"{escaped}"'



class Generator:
    def __init__(self, spec: dict) -> None:
        self.spec = spec
        self.schemas: dict = spec["components"]["schemas"]
        self.decls: list[list[str]] = []

    # -- types --------------------------------------------------------------

    def ref_name(self, ref: str) -> str:
        prefix = "#/components/schemas/"
        if not ref.startswith(prefix):
            raise ValueError(f"unsupported $ref {ref}")
        return ref[len(prefix):]

    def is_nullable(self, schema: dict) -> bool:
        if "$ref" in schema:
            return self.is_nullable(self.schemas[self.ref_name(schema["$ref"])])
        t = schema.get("type")
        return isinstance(t, list) and "null" in t

    def swift_type(self, schema: dict, owner: str, prop: str) -> tuple[str, bool]:
        """(Swift type without the optional mark, nullable?)"""
        for key in ("oneOf", "anyOf"):
            if key in schema:
                options = schema[key]
                non_null = [o for o in options if o.get("type") != "null"]
                if len(non_null) != 1 or len(options) != 2:
                    raise ValueError(f"{owner}.{prop}: only X-or-null {key} is supported")
                inner, _ = self.swift_type(non_null[0], owner, prop)
                return inner, True
        if "$ref" in schema:
            target = self.ref_name(schema["$ref"])
            return type_name(target), self.is_nullable(schema)
        t = schema.get("type")
        nullable = False
        if isinstance(t, list):
            rest = [x for x in t if x != "null"]
            nullable = len(rest) != len(t)
            if len(rest) != 1:
                raise ValueError(f"{owner}.{prop}: unsupported type list {t}")
            t = rest[0]
        if "enum" in schema and t == "string":
            name = owner + pascal(prop)
            self.emit_enum(name, schema)
            return name, nullable
        if t == "object":
            name = owner + pascal(prop)
            self.emit_struct(name, schema)
            return name, nullable
        if t == "array":
            inner, inner_null = self.swift_type(schema["items"], owner, prop + "_item")
            return f"[{inner}{'?' if inner_null else ''}]", nullable
        if t in PRIMITIVES:
            return PRIMITIVES[t], nullable
        raise ValueError(f"{owner}.{prop}: unsupported schema {schema}")

    def emit_enum(self, name: str, schema: dict) -> None:
        if schema.get("type") not in ("string", ["string"]):
            raise ValueError(f"{name}: only string enums are supported")
        lines = doc(schema.get("description"), "\t")
        lines.append(f"\tpublic enum {name}: String, Codable, Sendable, Hashable, CaseIterable {{")
        cases = [case_name(v) for v in schema["enum"]]
        if len(set(cases)) != len(cases):
            raise ValueError(f"{name}: enum values collide as Swift cases: {cases}")
        for case, value in zip(cases, schema["enum"], strict=True):
            lines.append(f"\t\tcase {case} = {swift_string(value)}")
        lines.append("\t}")
        self.decls.append(lines)

    def emit_struct(self, name: str, schema: dict) -> None:
        if schema.get("additionalProperties") is not False:
            raise ValueError(f"{name}: objects must set additionalProperties: false")
        required = set(schema.get("required", []))
        props = []
        for key in sorted(schema.get("properties", {})):
            sub = schema["properties"][key]
            swift, nullable = self.swift_type(sub, name, key)
            optional = nullable or key not in required
            props.append((key, camel(key), swift + ("?" if optional else ""), optional, sub))
        lines = doc(schema.get("description"), "\t")
        lines.append(f"\tpublic struct {name}: Codable, Sendable, Hashable {{")
        for key, field, swift, _, sub in props:
            lines += doc(sub.get("description"), "\t\t")
            lines.append(f"\t\tpublic var {field}: {swift}")
        if props:
            lines.append("")
            params = ", ".join(
                f"{f.strip('`')}: {s}{' = nil' if opt else ''}" for _, f, s, opt, _ in props)
            lines.append(f"\t\tpublic init({params}) {{")
            for _, field, _, _, _ in props:
                lines.append(f"\t\t\tself.{field.strip('`')} = {field.strip('`')}")
            lines.append("\t\t}")
            lines.append("")
            lines.append("\t\tenum CodingKeys: String, CodingKey {")
            for key, field, _, _, _ in props:
                lines.append(f"\t\t\tcase {field} = {swift_string(key)}")
            lines.append("\t\t}")
        else:
            lines.append("\t\tpublic init() {}")
        lines.append("\t}")
        self.decls.append(lines)

    def emit_schema(self, name: str) -> None:
        schema = self.schemas[name]
        t = schema.get("type")
        swift = type_name(name)
        if "enum" in schema and schema.get("type") == "string":
            self.emit_enum(swift, schema)
        elif t == "object":
            self.emit_struct(swift, schema)
        else:
            base, _ = self.swift_type({k: v for k, v in schema.items() if k != "description"},
                                      swift, "value")
            lines = doc(schema.get("description"), "\t")
            if self.is_nullable(schema):
                lines.append("\t/// Nullable: every use site is optional.")
            lines.append(f"\tpublic typealias {swift} = {base}")
            self.decls.append(lines)

    # -- operations ---------------------------------------------------------

    def resolve_param(self, param: dict) -> dict:
        if "$ref" in param:
            prefix = "#/components/parameters/"
            return self.spec["components"]["parameters"][param["$ref"][len(prefix):]]
        return param

    def operations(self) -> list[tuple[str, str, str, dict]]:
        ops = []
        for path, methods in self.spec["paths"].items():
            for method in ("get", "post", "put", "patch", "delete"):
                if method in methods:
                    ops.append((methods[method]["operationId"], method.upper(), path,
                                methods[method]))
        return sorted(ops)

    def response_type(self, op: dict) -> str:
        schema = op["responses"]["200"]["content"]["application/json"]["schema"]
        swift, _ = self.swift_type(schema, "Response", "body")
        return swift

    @staticmethod
    def qualify(swift: str) -> str:
        """``[Tag]?`` -> ``[API.Tag]?``: endpoint factories live outside ``API``."""
        builtin = set(PRIMITIVES.values())
        return re.sub(r"\b[A-Z]\w*\b",
                      lambda m: m.group(0) if m.group(0) in builtin else "API." + m.group(0),
                      swift)

    def emit_endpoints(self) -> list[str]:
        lines = []
        for op_id, method, path, op in self.operations():
            response = self.qualify(self.response_type(op))
            params = op.get("parameters", [])
            takes_filters = any(p.get("$ref") == FILTER_REF for p in params)
            args: list[str] = []
            path_expr = path.removeprefix("/api/v1/")
            query: list[str] = []
            for raw in params:
                if raw.get("$ref", "").startswith("#/components/parameters/") and takes_filters \
                        and raw["$ref"].rsplit("/", 1)[1] in FILTER_PARAMS:
                    continue
                p = self.resolve_param(raw)
                swift = self.qualify(self.swift_type(p["schema"], "Param", p["name"])[0])
                arg = camel(p["name"]).strip("`")
                if p["in"] == "path":
                    args.append(f"{arg}: {swift}")
                    path_expr = path_expr.replace("{" + p["name"] + "}", f"\\(pathSegment({arg}))")
                elif p["in"] == "query":
                    args.append(f"{arg}: {swift}? = nil")
                    query.append(f"query({swift_string(p['name'])}, {arg})")
                else:
                    raise ValueError(f"{op_id}: unsupported parameter location {p['in']}")
            if takes_filters:
                args.append("filters: FilterState")
            body = "nil"
            if "requestBody" in op:
                schema = op["requestBody"]["content"]["application/json"]["schema"]
                swift = self.qualify(self.swift_type(schema, "Request", "body")[0])
                args.insert(0, f"body: {swift}")
                body = "jsonBody(body)"
            authenticated = op.get("security", self.spec.get("security")) != []
            items = ("filters.queryItems" if takes_filters else "[]")
            if query:
                items = f"{items} + " + " + ".join(query) if takes_filters else \
                    " + ".join(query)
            lines += doc(op.get("summary"), "\t")
            lines.append(f"\tpublic static func {op_id}({', '.join(args)}) -> Endpoint<{response}>"
                         " {")
            lines.append("\t\tEndpoint(")
            lines.append(f"\t\t\toperationId: {swift_string(op_id)}, method: .{method.lower()}, "
                         f"path: \"{path_expr}\",")
            lines.append(f"\t\t\tquery: {items}, body: {body}, "
                         f"authenticated: {'true' if authenticated else 'false'})")
            lines.append("\t}")
            lines.append("")
        return lines

    # -- file ---------------------------------------------------------------

    def render(self, spec_text: str) -> str:
        for name in sorted(self.schemas):
            self.emit_schema(name)
        ops = self.operations()
        endpoint_lines = self.emit_endpoints()
        digest = hashlib.sha256(spec_text.encode()).hexdigest()
        out = [
            "// GENERATED by ios/scripts/gen_api_types.py from openapi/v1.json. Do not edit.",
            "// Regenerate: .venv/bin/python ios/scripts/gen_api_types.py",
            "",
            "import Foundation",
            "",
            "/// Every request and response type in the v1 contract.",
            "public enum API {",
            "\t/// SHA-256 of the openapi/v1.json these types were generated from.",
            f"\tpublic static let specDigest = {swift_string(digest)}",
            "",
            "\t/// The 200 response type of every operation, by operationId.",
            "\tpublic static let responseTypes: [String: any (Decodable & Sendable).Type] = [",
        ]
        out += [f"\t\t{swift_string(op_id)}: {self.response_type(op)}.self,"
                for op_id, _, _, op in ops]
        out += ["\t]", "}", "", "extension API {"]
        seen: set[str] = set()
        for decl in self.decls:
            key = "\n".join(decl)
            if key in seen:
                continue
            seen.add(key)
            out += decl + [""]
        if out[-1] == "":
            out.pop()
        out += ["}", "", "/// One factory per operation: `try await api.send(Endpoints.getMeta())`.",
                "public enum Endpoints {"]
        out += endpoint_lines
        out[-1:] = ["}"]
        return "\n".join(out) + "\n"


# The shared filter parameters FilterState.queryItems encodes (one place).
FILTER_PARAMS = {"colors", "outcomes", "terminations", "start", "end", "series",
                 "min_moves", "max_moves", "lens"}


def render() -> str:
    text = SPEC.read_text()
    return Generator(json.loads(text)).render(text)


def main(argv: list[str]) -> int:
    swift = render()
    if "--check" in argv:
        if not OUT.exists() or OUT.read_text() != swift:
            print(f"{OUT.name} is stale: run ios/scripts/gen_api_types.py")
            return 1
        return 0
    OUT.parent.mkdir(parents=True, exist_ok=True)
    if not OUT.exists() or OUT.read_text() != swift:
        OUT.write_text(swift)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
