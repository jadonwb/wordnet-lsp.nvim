--- Lightweight English morphology utility.
--- Generates candidate base-form (lemma) words for inflected English words.
--- Designed for pre-WordNet lookup: try candidates until one is found in the index.
---
--- This is NOT a full NLP lemmatizer — it uses suffix-stripping rules and a
--- dictionary of common irregular forms. It errs on the side of false positives
--- (generating incorrect candidates is fine; WordNet won't find them anyway).

local M = {}

--- Common irregular English word forms.
--- Maps lowercase inflected form → lowercase base lemma.
--- Covers the most common irregular verbs, nouns, and comparatives.
local IRREGULARS = {
  -- To be
  am = 'be', are = 'be', is = 'be', was = 'be', were = 'be', been = 'be', being = 'be',
  -- To have
  has = 'have', had = 'have', having = 'have',
  -- To do
  does = 'do', did = 'do', done = 'do', doing = 'do',
  -- To go
  went = 'go', gone = 'go', going = 'go', goes = 'go',
  -- Common irregular verbs (past, past participle, present participle)
  arose = 'arise', arisen = 'arise', arising = 'arise',
  awoke = 'awake', awoken = 'awake', awaking = 'awake',
  bore = 'bear', borne = 'bear', born = 'bear', bearing = 'bear',
  beat = 'beat', beaten = 'beat', beating = 'beat',
  became = 'become', becoming = 'become',
  began = 'begin', begun = 'begin', beginning = 'begin',
  bent = 'bend', bending = 'bend',
  bet = 'bet', betting = 'bet',
  bit = 'bite', bitten = 'bite', biting = 'bite',
  blew = 'blow', blown = 'blow', blowing = 'blow',
  broke = 'break', broken = 'break', breaking = 'break',
  brought = 'bring', bringing = 'bring',
  built = 'build', building = 'build',
  burnt = 'burn', burned = 'burn', burning = 'burn',
  burst = 'burst', bursting = 'burst',
  bought = 'buy', buying = 'buy',
  caught = 'catch', catching = 'catch',
  chose = 'choose', chosen = 'choose', choosing = 'choose',
  clung = 'cling', clinging = 'cling',
  came = 'come', coming = 'come',
  cost = 'cost', costing = 'cost',
  crept = 'creep', creeping = 'creep',
  cut = 'cut', cutting = 'cut',
  dealt = 'deal', dealing = 'deal',
  dug = 'dig', digging = 'dig',
  drew = 'draw', drawn = 'draw', drawing = 'draw',
  dreamt = 'dream', dreamed = 'dream', dreaming = 'dream',
  drank = 'drink', drunk = 'drink', drinking = 'drink',
  drove = 'drive', driven = 'drive', driving = 'drive',
  ate = 'eat', eaten = 'eat', eating = 'eat',
  fell = 'fall', fallen = 'fall', falling = 'fall',
  fed = 'feed', feeding = 'feed',
  felt = 'feel', feeling = 'feel',
  fought = 'fight', fighting = 'fight',
  found = 'find', finding = 'find',
  fled = 'flee', fleeing = 'flee',
  flew = 'fly', flown = 'fly', flying = 'fly',
  forbade = 'forbid', forbidden = 'forbid', forbidding = 'forbid',
  forgot = 'forget', forgotten = 'forget', forgetting = 'forget',
  forgave = 'forgive', forgiven = 'forgive', forgiving = 'forgive',
  froze = 'freeze', frozen = 'freeze', freezing = 'freeze',
  got = 'get', gotten = 'get', getting = 'get',
  gave = 'give', given = 'give', giving = 'give',
  grew = 'grow', grown = 'grow', growing = 'grow',
  hung = 'hang', hanging = 'hang',
  heard = 'hear', hearing = 'hear',
  hid = 'hide', hidden = 'hide', hiding = 'hide',
  hit = 'hit', hitting = 'hit',
  held = 'hold', holding = 'hold',
  hurt = 'hurt', hurting = 'hurt',
  kept = 'keep', keeping = 'keep',
  knelt = 'kneel', kneeling = 'kneel',
  knew = 'know', known = 'know', knowing = 'know',
  laid = 'lay', laying = 'lay',
  led = 'lead', leading = 'lead',
  leant = 'lean', leaned = 'lean', leaning = 'lean',
  leapt = 'leap', leaped = 'leap', leaping = 'leap',
  learnt = 'learn', learned = 'learn', learning = 'learn',
  left = 'leave', leaving = 'leave',
  lent = 'lend', lending = 'lend',
  let = 'let', letting = 'let',
  lay = 'lie', lain = 'lie', lying = 'lie',
  lit = 'light', lighted = 'light', lighting = 'light',
  lost = 'lose', losing = 'lose',
  made = 'make', making = 'make',
  meant = 'mean', meaning = 'mean',
  met = 'meet', meeting = 'meet',
  mistook = 'mistake', mistaken = 'mistake', mistaking = 'mistake',
  overcame = 'overcome', overcoming = 'overcome',
  paid = 'pay', paying = 'pay',
  proved = 'prove', proven = 'prove', proving = 'prove',
  put = 'put', putting = 'put',
  quit = 'quit', quitting = 'quit',
  read = 'read', reading = 'read',
  rode = 'ride', ridden = 'ride', riding = 'ride',
  rang = 'ring', rung = 'ring', ringing = 'ring',
  rose = 'rise', risen = 'rise', rising = 'rise',
  ran = 'run', running = 'run',
  said = 'say', saying = 'say',
  saw = 'see', seen = 'see', seeing = 'see',
  sought = 'seek', seeking = 'seek',
  sold = 'sell', selling = 'sell',
  sent = 'send', sending = 'send',
  set = 'set', setting = 'set',
  sewed = 'sew', sewn = 'sew', sewing = 'sew',
  shook = 'shake', shaken = 'shake', shaking = 'shake',
  shone = 'shine', shined = 'shine', shining = 'shine',
  shot = 'shoot', shooting = 'shoot',
  showed = 'show', shown = 'show', showing = 'show',
  shrank = 'shrink', shrunk = 'shrink', shrinking = 'shrink',
  shut = 'shut', shutting = 'shut',
  sang = 'sing', sung = 'sing', singing = 'sing',
  sank = 'sink', sunk = 'sink', sinking = 'sink',
  sat = 'sit', sitting = 'sit',
  slept = 'sleep', sleeping = 'sleep',
  slid = 'slide', sliding = 'slide',
  smelt = 'smell', smelled = 'smell', smelling = 'smell',
  sowed = 'sow', sown = 'sow', sowing = 'sow',
  spoke = 'speak', spoken = 'speak', speaking = 'speak',
  spelt = 'spell', spelled = 'spell', spelling = 'spell',
  spent = 'spend', spending = 'spend',
  spilt = 'spill', spilled = 'spill', spilling = 'spill',
  spun = 'spin', spinning = 'spin',
  spat = 'spit', spitting = 'spit',
  split = 'split', splitting = 'split',
  spoilt = 'spoil', spoiled = 'spoil', spoiling = 'spoil',
  spread = 'spread', spreading = 'spread',
  sprang = 'spring', sprung = 'spring', springing = 'spring',
  stood = 'stand', standing = 'stand',
  stole = 'steal', stolen = 'steal', stealing = 'steal',
  stuck = 'stick', sticking = 'stick',
  stung = 'sting', stinging = 'sting',
  stank = 'stink', stunk = 'stink', stinking = 'stink',
  struck = 'strike', stricken = 'strike', striking = 'strike',
  strove = 'strive', striven = 'strive', striving = 'strive',
  swore = 'swear', sworn = 'swear', swearing = 'swear',
  swept = 'sweep', sweeping = 'sweep',
  swam = 'swim', swum = 'swim', swimming = 'swim',
  swung = 'swing', swinging = 'swing',
  took = 'take', taken = 'take', taking = 'take',
  taught = 'teach', teaching = 'teach',
  tore = 'tear', torn = 'tear', tearing = 'tear',
  told = 'tell', telling = 'tell',
  thought = 'think', thinking = 'think',
  threw = 'throw', thrown = 'throw', throwing = 'throw',
  thrust = 'thrust', thrusting = 'thrust',
  trod = 'tread', trodden = 'tread', treading = 'tread',
  underwent = 'undergo', undergone = 'undergo', undergoing = 'undergo',
  understood = 'understand', understanding = 'understand',
  undertook = 'undertake', undertaken = 'undertake', undertaking = 'undertake',
  upset = 'upset', upsetting = 'upset',
  woke = 'wake', woken = 'wake', waking = 'wake',
  wore = 'wear', worn = 'wear', wearing = 'wear',
  wove = 'weave', woven = 'weave', weaving = 'weave',
  wept = 'weep', weeping = 'weep',
  won = 'win', winning = 'win',
  wound = 'wind', winding = 'wind',
  withdrew = 'withdraw', withdrawn = 'withdraw', withdrawing = 'withdraw',
  wrung = 'wring', wringing = 'wring',
  wrote = 'write', written = 'write', writing = 'write',
  -- Irregular comparatives / superlatives
  better = 'good', best = 'good',
  worse = 'bad', worst = 'bad',
  more = 'many', most = 'many',
  less = 'little', least = 'little',
  further = 'far', furthest = 'far', farther = 'far', farthest = 'far',
  elder = 'old', eldest = 'old',
  -- Irregular plurals
  children = 'child',
  men = 'man',
  women = 'woman',
  people = 'person', persons = 'person',
  teeth = 'tooth',
  feet = 'foot',
  mice = 'mouse',
  geese = 'goose',
  oxen = 'ox',
  lives = 'life',
  wives = 'wife',
  knives = 'knife',
  wolves = 'wolf',
  shelves = 'shelf',
  thieves = 'thief',
  leaves = 'leaf',
  selves = 'self',
  halves = 'half',
  calves = 'calf',
  elves = 'elf',
  loaves = 'loaf',
  scarves = 'scarf',
  hooves = 'hoof',
  -- Same form singular/plural
  sheep = 'sheep',
  deer = 'deer',
  fish = 'fish',
  series = 'series',
  species = 'species',
  aircraft = 'aircraft',
  offspring = 'offspring',
}

--- Generate candidate base-form (lemma) words for a given inflected word.
--- Returns a list of candidate strings ordered by likelihood (most likely first).
--- The caller should iterate and test each candidate against WordNet.
---
--- The algorithm:
--- 1. Exact match (pass-through)
--- 2. Irregular form lookup
--- 3. Plural noun suffixes: -s, -es, -ies
--- 4. Past tense suffixes: -ed, -d, -ied
--- 5. Present participle: -ing
--- 6. Comparative/superlative: -er, -est, -ier, -iest
--- 7. Adverb: -ly, -ily
--- 8. Derived forms: -ment, -ness, -tion, -able, -ible, -al, -ful
---
--- @param word string The word to lemmatize (case-insensitive)
--- @return string[] Ordered list of candidate lemmas
function M.get_candidate_lemmas(word)
  local lower = word:lower()
  local candidates = {}
  local seen = {}

  local function add(c)
    if not seen[c] then
      seen[c] = true
      table.insert(candidates, c)
    end
  end

  -- 1. Exact match (always try the word as-is first)
  add(lower)

  -- 2. Irregular form (highest confidence if exists)
  local irregular = IRREGULARS[lower]
  if irregular then
    add(irregular)
  end

  local len = #lower

  -- 3. Plural / 3rd-person singular (-s, -es, -ies)
  if len > 3 then
    if lower:sub(-3) == 'ies' then
      add(lower:sub(1, -4) .. 'y')       -- "happies" → "happy"
    elseif lower:sub(-2) == 'es' then
      add(lower:sub(1, -3))               -- "boxes" → "box"
      add(lower:sub(1, -3) .. 'e')        -- "hates" → "hate"
    elseif lower:sub(-1) == 's' then
      add(lower:sub(1, -2))               -- "cats" → "cat"
    end
  end

  -- 4. Past tense (-ed, -d, -ied)
  if len > 3 then
    if lower:sub(-3) == 'ied' then
      add(lower:sub(1, -4) .. 'y')        -- "carried" → "carry"
    elseif lower:sub(-2) == 'ed' then
      add(lower:sub(1, -3))               -- "started" → "start"
      -- Handle doubled consonants: "stopped" → "stop"
      if len > 4 then
        local c1 = lower:sub(len - 3, len - 3)
        local c2 = lower:sub(len - 4, len - 4)
        if c1 == c2 then
          add(lower:sub(1, -5) .. c1)     -- "stopped" → "stop"
        end
      end
    elseif lower:sub(-1) == 'd' and lower:sub(-2, -2) ~= 'd' then
      add(lower:sub(1, -2))               -- "loved" → "love"
    end
  end

  -- 5. Present participle (-ing)
  if len > 4 and lower:sub(-3) == 'ing' then
    add(lower:sub(1, -4))                  -- "starting" → "start"
    add(lower:sub(1, -4) .. 'e')           -- "making" → "make"
    -- Handle doubled consonants: "running" → "run"
    if len > 5 then
      local c1 = lower:sub(len - 4, len - 4)
      local c2 = lower:sub(len - 5, len - 5)
      if c1 == c2 then
        add(lower:sub(1, -6) .. c1)        -- "running" → "run"
      end
    end
    -- Handle -ying → -ie: "dying" → "die"
    if len > 5 and lower:sub(-4, -4) == 'y' then
      add(lower:sub(1, -5) .. 'ie')        -- "dying" → "die"
    end
  end

  -- 6. Comparative (-er, -ier) and superlative (-est, -iest)
  if len > 4 then
    if lower:sub(-4) == 'iest' then
      add(lower:sub(1, -5) .. 'y')         -- "happiest" → "happy"
    elseif lower:sub(-3) == 'est' then
      add(lower:sub(1, -4))                 -- "biggest" → "big"
      -- Handle doubled consonants: "biggest" → "big"
      if len > 5 then
        local c1 = lower:sub(len - 4, len - 4)
        local c2 = lower:sub(len - 5, len - 5)
        if c1 == c2 then
          add(lower:sub(1, -6) .. c1)       -- "biggest" → "big"
        end
      end
    end
    if lower:sub(-3) == 'ier' then
      add(lower:sub(1, -4) .. 'y')          -- "happier" → "happy"
    elseif lower:sub(-2) == 'er' and len > 3 then
      -- Skip if it's a word ending in 'er' naturally (like "father")
      add(lower:sub(1, -3))                  -- "bigger" → "big"
      add(lower:sub(1, -3) .. 'e')           -- "nicer" → "nice"
      -- Handle doubled consonants
      if len > 4 then
        local c1 = lower:sub(len - 3, len - 3)
        local c2 = lower:sub(len - 4, len - 4)
        if c1 == c2 then
          add(lower:sub(1, -5) .. c1)        -- "bigger" → "big"
        end
      end
    end
  end

  -- 7. Adverb (-ly, -ily)
  if len > 4 then
    if lower:sub(-3) == 'ily' then
      add(lower:sub(1, -4) .. 'y')          -- "happily" → "happy"
    elseif lower:sub(-2) == 'ly' then
      add(lower:sub(1, -3))                  -- "quickly" → "quick"
    end
  end

  -- 8. Derived forms (lower priority, try these last)
  if len > 5 then
    if lower:sub(-4) == 'ness' then
      add(lower:sub(1, -5))                  -- "happiness" → "happy"
    end
    if lower:sub(-4) == 'ment' then
      add(lower:sub(1, -5))                  -- "enjoyment" → "enjoy"
    end
    if lower:sub(-4) == 'able' then
      add(lower:sub(1, -5))                  -- "readable" → "read"
      add(lower:sub(1, -5) .. 'e')           -- "likable" → "like"
    end
    if lower:sub(-4) == 'ible' then
      add(lower:sub(1, -5))                  -- "possible" → "poss"
    end
    if lower:sub(-3) == 'ful' then
      add(lower:sub(1, -4))                  -- "helpful" → "help"
    end
    if lower:sub(-3) == 'ion' then
      add(lower:sub(1, -4))                  -- "creation" → "creat"
      add(lower:sub(1, -4) .. 'e')            -- "creation" → "create"
    end
  end

  return candidates
end

return M
