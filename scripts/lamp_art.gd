extends RefCounted
## Original matte linen/brass lamp illustration. Shared by world, catalog,
## drag preview and the static atlas through IllustratedCafe._lamp.
## Art remains inside Rect2(-22,-87,44,98); gameplay data is untouched.
## Reserved attachment for a future lighting pass; no light node or glow here.
const LIGHT_ANCHOR := Vector2(0,-61)

static func draw_lamp(a: Node2D,p: Vector2) -> void:
	# soft contact shadow
	a.ellipse(p+Vector2(1,2),Vector2(13,5.1),"80745b16")
	# sage lower base
	a.ellipse(p+Vector2(0,0.9),Vector2(12,5.2),"798a72")
	# enamel base face
	a.ellipse(p+Vector2(0,-0.7),Vector2(11.7,5),"9eae8d")
	# base soft upper plane
	a.ellipse(p+Vector2(-0.7,-1.9),Vector2(9.5,3.3),"b6c29e")
	# base front bevel
	a.poly([p+Vector2(11.3,-0.4),p+Vector2(11.0829,0.4389),p+Vector2(10.4398,1.2455),p+Vector2(9.3956,1.989),p+Vector2(7.9903,2.6406),p+Vector2(6.2779,3.1753),p+Vector2(4.3243,3.5727),p+Vector2(2.2045,3.8174),p+Vector2(0,3.9),p+Vector2(-2.2045,3.8174),p+Vector2(-4.3243,3.5727),p+Vector2(-6.2779,3.1753),p+Vector2(-7.9903,2.6406),p+Vector2(-9.3956,1.989),p+Vector2(-10.4398,1.2455),p+Vector2(-11.0829,0.4389),p+Vector2(-11.3,-0.4),p+Vector2(-11.3,-1.1),p+Vector2(-11.0829,-0.2611),p+Vector2(-10.4398,0.5455),p+Vector2(-9.3956,1.289),p+Vector2(-7.9903,1.9406),p+Vector2(-6.2779,2.4753),p+Vector2(-4.3243,2.8727),p+Vector2(-2.2045,3.1174),p+Vector2(0,3.2),p+Vector2(2.2045,3.1174),p+Vector2(4.3243,2.8727),p+Vector2(6.2779,2.4753),p+Vector2(7.9903,1.9406),p+Vector2(9.3956,1.289),p+Vector2(10.4398,0.5455),p+Vector2(11.0829,-0.2611),p+Vector2(11.3,-1.1)],"90a080")
	# socket lower collar
	a.ellipse(p+Vector2(0,-2.1),Vector2(3.5,1.7),"887d5b")
	# socket neck
	a.poly([p+Vector2(-2.9,-6.2),p+Vector2(2.9,-6.2),p+Vector2(3.1,-2.4),p+Vector2(-3.1,-2.4)],"b5a477")
	# socket crown
	a.ellipse(p+Vector2(0,-6.2),Vector2(2.9,1.2),"cfbd8e")
	# stem shade edge
	a.line(p+Vector2(0,-6),p+Vector2(0,-61),"8f835d",3.7)
	# brushed brass stem
	a.line(p+Vector2(-0.2,-6),p+Vector2(-0.2,-61),"b6a575",2.6)
	# stem narrow highlight
	a.line(p+Vector2(-0.8,-7),p+Vector2(-0.8,-60),"d4c295",0.65)
	# lower stem ferrule
	a.ellipse(p+Vector2(0,-10.3),Vector2(2.05,0.9),"a5966b")
	# ferrule light lip
	a.line(p+Vector2(-1.7,-10.8),p+Vector2(1.3,-10.8),"d4c397",0.55)
	# shade neck joint
	a.ellipse(p+Vector2(0,-57.6),Vector2(2.5,1.1),"968965")
	# shade neck
	a.line(p+Vector2(0,-58.6),p+Vector2(0,-64),"c4b181",3.4)
	# shade linen silhouette
	a.poly([p+Vector2(-10,-83),p+Vector2(10,-83),p+Vector2(18,-61),p+Vector2(-18,-61)],"e4d5b1")
	# left folded fabric
	a.poly([p+Vector2(-10,-83),p+Vector2(-5.8,-83),p+Vector2(-9,-61),p+Vector2(-18,-61)],"dccba5")
	# central fabric face
	a.poly([p+Vector2(-5.8,-83),p+Vector2(4.5,-83),p+Vector2(7.8,-61),p+Vector2(-9,-61)],"efe2c1")
	# right folded fabric
	a.poly([p+Vector2(4.5,-83),p+Vector2(10,-83),p+Vector2(18,-61),p+Vector2(7.8,-61)],"d9c7a2")
	# left soft fabric layer
	a.poly([p+Vector2(-5.3,-81.6),p+Vector2(-3.5,-81.5),p+Vector2(-4.5,-62),p+Vector2(-7.7,-62)],"e7d9b7")
	# central soft fabric layer
	a.poly([p+Vector2(-2.8,-81.5),p+Vector2(1.2,-81.5),p+Vector2(2.8,-62),p+Vector2(-3.8,-62)],"f2e7cb")
	# left panel seam
	a.line(p+Vector2(-6,-81.8),p+Vector2(-9.5,-62),"d0bd97",0.55)
	# right panel seam
	a.line(p+Vector2(5.7,-81.8),p+Vector2(10,-62),"cdb992",0.55)
	# left seam soft edge
	a.line(p+Vector2(-5.2,-81.7),p+Vector2(-8.6,-62),"f0e4c6",0.45)
	# left outer binding
	a.line(p+Vector2(-9.8,-82.6),p+Vector2(-17.3,-61.4),"d5c097",0.7)
	# right outer binding
	a.line(p+Vector2(9.8,-82.6),p+Vector2(17.3,-61.4),"c5b28b",0.7)
	# bottom fabric binding
	a.ellipse(p+Vector2(0,-61),Vector2(18,5.6),"d3be95")
	# recessed shade opening
	a.ellipse(p+Vector2(0,-61.5),Vector2(16.3,3.9),"bca982")
	# matte inner lining
	a.ellipse(p+Vector2(-0.5,-62.2),Vector2(13.7,2.8),"ddd0ae")
	# small recessed socket
	a.ellipse(p+Vector2(0,-61.2),Vector2(2.25,1.15),"b09c72")
	# front hem piping
	a.poly([p+Vector2(17.8,-61),p+Vector2(17.458,-59.927),p+Vector2(16.4451,-58.8952),p+Vector2(14.8002,-57.9444),p+Vector2(12.5865,-57.1109),p+Vector2(9.8892,-56.4269),p+Vector2(6.8118,-55.9187),p+Vector2(3.4726,-55.6057),p+Vector2(0,-55.5),p+Vector2(-3.4726,-55.6057),p+Vector2(-6.8118,-55.9187),p+Vector2(-9.8892,-56.4269),p+Vector2(-12.5865,-57.1109),p+Vector2(-14.8002,-57.9444),p+Vector2(-16.4451,-58.8952),p+Vector2(-17.458,-59.927),p+Vector2(-17.8,-61),p+Vector2(-17.8,-61.85),p+Vector2(-17.458,-60.777),p+Vector2(-16.4451,-59.7452),p+Vector2(-14.8002,-58.7944),p+Vector2(-12.5865,-57.9609),p+Vector2(-9.8892,-57.2769),p+Vector2(-6.8118,-56.7687),p+Vector2(-3.4726,-56.4557),p+Vector2(0,-56.35),p+Vector2(3.4726,-56.4557),p+Vector2(6.8118,-56.7687),p+Vector2(9.8892,-57.2769),p+Vector2(12.5865,-57.9609),p+Vector2(14.8002,-58.7944),p+Vector2(16.4451,-59.7452),p+Vector2(17.458,-60.777),p+Vector2(17.8,-61.85)],"ead9b5")
	# front hem lower edge
	a.poly([p+Vector2(16.8777,-60.0895),p+Vector2(16.2339,-59.1863),p+Vector2(15.0577,-58.3327),p+Vector2(13.3876,-57.5568),p+Vector2(11.2784,-56.884),p+Vector2(8.7993,-56.3363),p+Vector2(6.0316,-55.9318),p+Vector2(3.0661,-55.6836),p+Vector2(0,-55.6),p+Vector2(-3.0661,-55.6836),p+Vector2(-6.0316,-55.9318),p+Vector2(-8.7993,-56.3363),p+Vector2(-11.2784,-56.884),p+Vector2(-13.3876,-57.5568),p+Vector2(-15.0577,-58.3327),p+Vector2(-16.2339,-59.1863),p+Vector2(-16.8777,-60.0895),p+Vector2(-16.8777,-60.3695),p+Vector2(-16.2339,-59.4663),p+Vector2(-15.0577,-58.6127),p+Vector2(-13.3876,-57.8368),p+Vector2(-11.2784,-57.164),p+Vector2(-8.7993,-56.6163),p+Vector2(-6.0316,-56.2118),p+Vector2(-3.0661,-55.9636),p+Vector2(0,-55.88),p+Vector2(3.0661,-55.9636),p+Vector2(6.0316,-56.2118),p+Vector2(8.7993,-56.6163),p+Vector2(11.2784,-57.164),p+Vector2(13.3876,-57.8368),p+Vector2(15.0577,-58.6127),p+Vector2(16.2339,-59.4663),p+Vector2(16.8777,-60.3695)],"c4af85")
	# top bound rim
	a.ellipse(p+Vector2(0,-82.8),Vector2(10,2.05),"d3bf9b")
	# top rim soft face
	a.ellipse(p+Vector2(-0.3,-83.1),Vector2(9.1,1.25),"f0e4c8")
