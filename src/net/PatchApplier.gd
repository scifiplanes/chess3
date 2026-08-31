extends RefCounted
class_name PatchApplier

# Minimal JSON-pointer-ish patch ops applier for v0 protocol.
# Supports ops: set, inc (int), push (array append).

static func apply_ops(state: Variant, ops: Array) -> Variant:
	var s: Variant = state
	for op_any in ops:
		if typeof(op_any) != TYPE_DICTIONARY:
			continue
		var op: Dictionary = op_any
		var kind := str(op.get("op", ""))
		var path := str(op.get("path", ""))
		match kind:
			"set":
				s = _set_path(s, path, op.get("value"))
			"inc":
				s = _inc_path(s, path, int(op.get("value", 0)))
			"push":
				s = _push_path(s, path, op.get("value"))
			_:
				continue
	return s

static func _split_path(path: String) -> Array[String]:
	if path == "" or path == "/":
		return []
	var p := path
	if p.begins_with("/"):
		p = p.substr(1)
	var parts := p.split("/", false)
	var out: Array[String] = []
	for part in parts:
		# Minimal unescape: JSON Pointer uses ~1 for / and ~0 for ~
		out.append(part.replace("~1", "/").replace("~0", "~"))
	return out

static func _clone_container(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		return (v as Dictionary).duplicate(true)
	if typeof(v) == TYPE_ARRAY:
		return (v as Array).duplicate(true)
	return v

static func _ensure_container_for_next(next_key: String) -> Variant:
	# If the next segment is a number, prefer Array; otherwise Dictionary.
	if next_key.is_valid_int():
		return []
	return {}

static func _set_path(root: Variant, path: String, value: Variant) -> Variant:
	var parts := _split_path(path)
	if parts.is_empty():
		return value

	var out_root: Variant = _clone_container(root)
	var cur: Variant = out_root

	for i in range(parts.size()):
		var key := parts[i]
		var is_last := i == parts.size() - 1

		if typeof(cur) == TYPE_DICTIONARY:
			var d: Dictionary = cur
			if is_last:
				d[key] = value
			else:
				if not d.has(key) or (typeof(d[key]) != TYPE_DICTIONARY and typeof(d[key]) != TYPE_ARRAY):
					d[key] = _ensure_container_for_next(parts[i + 1])
				else:
					d[key] = _clone_container(d[key])
				cur = d[key]
		elif typeof(cur) == TYPE_ARRAY:
			var a: Array = cur
			if not key.is_valid_int():
				return out_root
			var idx := int(key)
			while a.size() <= idx:
				a.append(null)
			if is_last:
				a[idx] = value
			else:
				if a[idx] == null or (typeof(a[idx]) != TYPE_DICTIONARY and typeof(a[idx]) != TYPE_ARRAY):
					a[idx] = _ensure_container_for_next(parts[i + 1])
				else:
					a[idx] = _clone_container(a[idx])
				cur = a[idx]
		else:
			# Cannot traverse primitives; replace with container and keep going (best-effort).
			cur = {}

	return out_root

static func _get_path(root: Variant, path: String) -> Variant:
	var parts := _split_path(path)
	var cur: Variant = root
	for key in parts:
		if typeof(cur) == TYPE_DICTIONARY:
			var d: Dictionary = cur
			if not d.has(key):
				return null
			cur = d[key]
		elif typeof(cur) == TYPE_ARRAY:
			var a: Array = cur
			if not key.is_valid_int():
				return null
			var idx := int(key)
			if idx < 0 or idx >= a.size():
				return null
			cur = a[idx]
		else:
			return null
	return cur

static func _inc_path(root: Variant, path: String, delta: int) -> Variant:
	var cur_val: Variant = _get_path(root, path)
	var base := int(cur_val) if cur_val != null else 0
	return _set_path(root, path, base + delta)

static func _push_path(root: Variant, path: String, value: Variant) -> Variant:
	var cur_val: Variant = _get_path(root, path)
	var arr: Array = []
	if typeof(cur_val) == TYPE_ARRAY:
		arr = (cur_val as Array).duplicate(true)
	arr.append(value)
	return _set_path(root, path, arr)

