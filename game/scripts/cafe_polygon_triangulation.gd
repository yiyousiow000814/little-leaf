extends RefCounted
## Preserve submitted vertices; normalize only the triangulation problem.
## Projection may collapse adjacent curve samples to the exact same pixel.
static func indices(points:PackedVector2Array)->PackedInt32Array:
 if points.size()<3:return PackedInt32Array()
 var normalized=PackedVector2Array();var source_indices=PackedInt32Array()
 var origin=points[0];var extent=0.0
 for point in points:extent=maxf(extent,maxf(absf(point.x-origin.x),absf(point.y-origin.y)))
 if extent<=.000001:return PackedInt32Array()
 for index in points.size():
  if not source_indices.is_empty() and points[index]==points[source_indices[-1]]:continue
  normalized.append((points[index]-origin)*(256.0/extent));source_indices.append(index)
 if source_indices.size()>1 and points[source_indices[0]]==points[source_indices[-1]]:
  normalized.remove_at(normalized.size()-1);source_indices.remove_at(source_indices.size()-1)
 if normalized.size()<3:return PackedInt32Array()
 var result=Geometry2D.triangulate_polygon(normalized)
 if result.is_empty():
  var signed_area=0.0
  for i in range(1,normalized.size()-1):signed_area+=(normalized[i]-normalized[0]).cross(normalized[i+1]-normalized[0])
  if absf(signed_area)>.0001:push_error("Nondegenerate overview contour failed stable triangulation")
 for index in result.size():result[index]=source_indices[result[index]]
 return result
