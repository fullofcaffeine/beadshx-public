# Upgrade sources cannot be newer than the fork's pinned compatibility target.
def version:
  capture("^v(?<major>[0-9]+)\\.(?<minor>[0-9]+)\\.(?<patch>[0-9]+)$")
  | [.major, .minor, .patch] | map(tonumber);

if ($count | type) != "number" or $count < 1 or ($count | floor) != $count
then error("release count must be a positive integer") else . end
| ($target | version) as $ceiling
| add
| map(select(.draft == false and .prerelease == false)
      | .tag_name
      | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
      | {tag: ., version: version}
      | select(.version <= $ceiling))
| unique_by(.version) | sort_by(.version) | reverse
| .[:$count] | map(.tag)
| if length == 0 then error("no supported upgrade source releases") else . end
