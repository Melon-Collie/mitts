class_name RinkMarkings

# The ice's painted markings that play does not read, sized from the NHL
# rulebook (Rule 1). HockeyRink paints them; test_board_ad_layout holds the
# in-ice ads clear of them. Lines and dots play reads stay in GameRules.

const FACEOFF_CIRCLE_RADIUS_M: float = 4.572     # 15 ft
const FACEOFF_DOT_RADIUS_M: float = 0.3048       # 2 ft spots
const CENTER_ICE_DOT_RADIUS_M: float = 0.1524    # 12 in spot
# Hash marks: a pair either side of each end-zone circle, running out from it
# parallel to the goal line, 2 ft long and 5 ft 7 in apart.
const HASH_MARK_LENGTH_M: float = 0.6096
const HASH_MARK_SPACING_M: float = 1.7018
# Goalkeeper's restricted area behind each net: 8 ft outside each post on the
# goal line (11 ft off centre), 14 ft off centre at the end boards.
const TRAPEZOID_GOAL_LINE_HALF_M: float = 3.3528
const TRAPEZOID_BOARDS_HALF_M: float = 4.2672
# Referee's crease: a 10 ft semicircle off the boards in front of the
# officials' table (the −X boards, at centre ice).
const REFEREE_CREASE_RADIUS_M: float = 3.048
