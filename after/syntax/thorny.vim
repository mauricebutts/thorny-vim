" Full message body regions — span from speaker label to the next speaker or separator
syn region ThornyUser   start="^You:"    end="^\ze\(Claude:\|─\)" keepend
syn region ThornyClaude start="^Claude:" end="^\ze\(You:\|─\)"    keepend

" Diff highlights inside pending edit blocks (override region colors)
syn match ThornyDiffAdd    "^│  +.*" containedin=ThornyClaude,ThornyUser
syn match ThornyDiffDelete "^│  -.*" containedin=ThornyClaude,ThornyUser

highlight default link ThornyUser       Identifier
highlight default link ThornyClaude     String
highlight default link ThornyDiffAdd    DiffAdd
highlight default link ThornyDiffDelete DiffDelete
