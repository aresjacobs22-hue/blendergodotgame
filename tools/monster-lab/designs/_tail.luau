
---------------------------------------------------------------------------

function Designs.build(kind: string, options: any?): any
	local d = Designs[kind]
	local b, joints = newBuilder(kind, d.height)
	local head = d.build(b, options and options.decoy)
	return { model = b.model, root = b.root, head = head, joints = joints, rootHeight = d.height, kind = kind }
end

return Designs
