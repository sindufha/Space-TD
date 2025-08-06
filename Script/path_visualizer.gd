extends Line2D

func _ready():
	update_path_visual()

func update_path_visual():
	var path = get_parent() as Path2D
	if path and path.curve:
		clear_points()
		
		# Ambil titik-titik sepanjang curve
		var curve = path.curve
		var length = curve.get_baked_length()
		var step = 10.0  # Jarak antar titik visual
		
		for i in range(int(length / step) + 1):
			var offset = i * step
			var point = curve.sample_baked(offset)
			add_point(point)
		
		# Set tampilan line
		width = 8.0
		default_color = Color.BROWN
		begin_cap_mode = Line2D.LINE_CAP_ROUND
		end_cap_mode = Line2D.LINE_CAP_ROUND
