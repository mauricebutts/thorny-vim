" Full message body regions — span from speaker label to the next speaker or separator
syn region ThornyUser      start="^You:"                    end="^\ze\(You:\|─\)" keepend
syn region ThornyAssistant start="^\(You: \)\@!\w\+: "     end="^\ze\(You:\|─\)" keepend

" Diff highlights inside pending edit blocks (override region colors)
syn match ThornyDiffAdd    "^│  +.*" containedin=ThornyAssistant,ThornyUser
syn match ThornyDiffDelete "^│  -.*" containedin=ThornyAssistant,ThornyUser

highlight default link ThornyUser       Identifier
highlight default link ThornyAssistant  String
highlight default link ThornyDiffAdd    DiffAdd
highlight default link ThornyDiffDelete DiffDelete
