class_name GameOverSummary
extends RefCounted
## What the game-over screen shows of a finished match. HUD fills it from the
## live game; GameOverPopup only presents it.

## The local player's own result, tagged over the winner line; NONE for a tie
## or a spectator.
enum Personal { NONE, VICTORY, DEFEAT }

var home_score: int = 0
var away_score: int = 0
## The clubs the two sides played as; -1 before they are known.
var home_club: int = -1
var away_club: int = -1
var result_text: String = ""
var result_color: Color = Color.WHITE
var personal: Personal = Personal.NONE

## The stars, best first, up to three: an empty title is no title, an empty line
## no stat line.
var star_names: Array[String] = []
var star_lines: Array[String] = []
var star_titles: Array[String] = []
var star_clubs: Array[int] = []
