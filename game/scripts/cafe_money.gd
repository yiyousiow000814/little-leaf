extends RefCounted
static func amount(value:int)->String:
	var digits=str(absi(value));var groups=PackedStringArray()
	while digits.length()>3:
		groups.insert(0,digits.right(3));digits=digits.left(digits.length()-3)
	groups.insert(0,digits)
	return ("−" if value<0 else "")+",".join(groups)
