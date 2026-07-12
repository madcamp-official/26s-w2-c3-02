class_name RingTexture
extends RefCounted

## TextureProgressBar에 쓸 도넛(링) 모양 텍스처를 런타임에 생성한다.
## 별도 이미지 에셋 없이, 바깥/안쪽 반지름 사이만 칠해서 도넛 형태를 만든다.

static func generate(size: int, radius_outer: float, radius_inner: float, color: Color) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var edge := 1.0 # 가장자리 안티에일리어싱 폭(px)
	for y in range(size):
		for x in range(size):
			var dist: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var outer_alpha: float = clamp((radius_outer - dist + edge) / edge, 0.0, 1.0)
			var inner_alpha: float = clamp((dist - radius_inner + edge) / edge, 0.0, 1.0)
			var alpha: float = min(outer_alpha, inner_alpha)
			if alpha > 0.0:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
	return ImageTexture.create_from_image(image)
