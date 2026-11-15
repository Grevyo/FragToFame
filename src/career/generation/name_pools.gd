class_name NamePools
extends RefCounted
## Name material for generated professionals and organisations. Given names and surnames are
## ordinary common names; nicknames and organisation names are original word combinations and
## deliberately avoid real esports players and organisations.

## nation id → culture group
const NATION_CULTURE: Dictionary[String, String] = {
	"gb": "anglo", "ie": "anglo", "us": "anglo", "ca": "anglo", "au": "anglo", "nz": "anglo", "za": "anglo",
	"se": "nordic", "no": "nordic", "dk": "nordic", "fi": "nordic", "ee": "nordic",
	"de": "germanic", "nl": "germanic", "be": "germanic", "hu": "germanic",
	"fr": "romance", "es": "romance", "pt": "romance", "it": "romance", "ro": "romance",
	"pl": "slavic", "cz": "slavic", "ua": "slavic", "bg": "slavic", "rs": "slavic",
	"br": "latin", "ar": "latin", "cl": "latin", "mx": "latin",
	"jp": "japanese", "kr": "korean", "cn": "chinese", "mn": "mongolian",
	"id": "sea", "ph": "sea", "tr": "turkish", "il": "levant", "eg": "levant",
}

const FIRST_NAMES: Dictionary[String, Array] = {
	"anglo": ["James", "Oliver", "Harry", "Jack", "Thomas", "Ethan", "Noah", "Liam", "Ryan", "Connor",
		"Callum", "Lewis", "Owen", "Dylan", "Mason", "Aaron", "Jordan", "Tyler", "Nathan", "Sean",
		"Rowan", "Elliot", "Reece", "Kieran", "Adam", "Mia", "Grace", "Chloe", "Ella", "Ava"],
	"nordic": ["Erik", "Lars", "Oskar", "Emil", "Axel", "Viktor", "Henrik", "Magnus", "Jonas", "Rasmus",
		"Mikkel", "Anton", "Elias", "Sander", "Joel", "Nils", "Teemu", "Aleksi", "Kasper", "Linnea"],
	"germanic": ["Lukas", "Jonas", "Felix", "Max", "Paul", "Leon", "Niklas", "Tim", "Daan", "Sem",
		"Bram", "Jens", "Ruben", "Thijs", "Florian", "Moritz", "Bence", "Levente", "Lena", "Sophie"],
	"romance": ["Hugo", "Lucas", "Mathis", "Adrien", "Pablo", "Javier", "Diego", "Marco", "Luca",
		"Matteo", "Tiago", "Rui", "Andrei", "Mihai", "Bastien", "Enzo", "Alvaro", "Nuno", "Elena", "Ines"],
	"slavic": ["Jakub", "Kacper", "Mateusz", "Ondrej", "Tomas", "Dmytro", "Oleksii", "Andriy", "Bogdan",
		"Nikola", "Stefan", "Milan", "Ivan", "Petar", "Filip", "Marek", "Wiktor", "Yaroslav", "Anna", "Zofia"],
	"latin": ["Gabriel", "Rafael", "Joao", "Mateus", "Thiago", "Leonardo", "Santiago", "Matias",
		"Joaquin", "Benjamin", "Felipe", "Bruno", "Vinicius", "Emiliano", "Alejandro", "Ignacio",
		"Gustavo", "Caio", "Valentina", "Camila"],
	"japanese": ["Haruto", "Ren", "Sota", "Yuto", "Kaito", "Riku", "Daiki", "Takumi", "Kenta", "Shun",
		"Yuki", "Hiroto", "Kazuki", "Sora", "Ayaka"],
	"korean": ["Minjun", "Seojun", "Doyun", "Jiho", "Hyunwoo", "Jaewon", "Taeyang", "Sungmin",
		"Donghyun", "Junho", "Yerin", "Jisoo", "Seungwoo", "Kyungmin", "Hajun"],
	"chinese": ["Wei", "Hao", "Jun", "Lei", "Ming", "Chen", "Yang", "Bo", "Tao", "Zhen", "Xin",
		"Kai", "Long", "Rui", "Lan"],
	"mongolian": ["Temuujin", "Bat-Erdene", "Ganbold", "Munkh", "Bilguun", "Enkhjin", "Tuvshin",
		"Erdem", "Sukh", "Altan"],
	"sea": ["Rizky", "Bayu", "Dimas", "Arif", "Andi", "Miguel", "Paolo", "Carlo", "Jericho", "Rafael",
		"Kevin", "Gilang", "Fajar", "Joshua", "Angelo"],
	"turkish": ["Emre", "Burak", "Mert", "Can", "Kerem", "Ozan", "Baran", "Arda", "Yusuf", "Efe",
		"Kaan", "Deniz", "Eren", "Selin", "Elif"],
	"levant": ["Omar", "Youssef", "Karim", "Amir", "Noam", "Itai", "Ariel", "Tamer", "Hassan", "Eitan",
		"Ziad", "Nadav", "Sami", "Layla", "Maya"],
}

const LAST_NAMES: Dictionary[String, Array] = {
	"anglo": ["Hartley", "Walker", "Bennett", "Turner", "Fletcher", "Holloway", "Marsh", "Carter",
		"Whitlock", "Hughes", "Barnes", "Doyle", "Fraser", "Morgan", "Pryce", "Sutton", "Ashdown",
		"Kendrick", "Lowell", "Brennan", "Calloway", "Merritt", "Thornton", "Rowe", "Gallagher"],
	"nordic": ["Lindqvist", "Berg", "Nyström", "Halvorsen", "Dahl", "Sandberg", "Holm", "Virtanen",
		"Korhonen", "Lund", "Ekberg", "Strand", "Mikkelsen", "Aalto", "Tamm", "Sepp", "Kask", "Vik"],
	"germanic": ["Becker", "Hoffmann", "Krüger", "Vogel", "Brandt", "de Vries", "Jansen", "Visser",
		"Peeters", "Claes", "Wouters", "Kovács", "Szabó", "Lange", "Richter", "Engel", "Bakker", "Maes"],
	"romance": ["Moreau", "Lefèvre", "Girard", "Navarro", "Romero", "Ortega", "Ferraro", "Conti",
		"Marino", "Costa", "Ferreira", "Almeida", "Popescu", "Ionescu", "Dumont", "Vidal", "Russo", "Silva"],
	"slavic": ["Nowak", "Kowalczyk", "Wiśniewski", "Novák", "Dvořák", "Kovalenko", "Shevchuk",
		"Bondar", "Petrović", "Jovanović", "Ivanov", "Georgiev", "Horák", "Zielinski", "Marchenko", "Savić"],
	"latin": ["Oliveira", "Santos", "Pereira", "Souza", "Lima", "Gómez", "Fernández", "Rojas",
		"Morales", "Herrera", "Castillo", "Vargas", "Ribeiro", "Carvalho", "Mendoza", "Acosta"],
	"japanese": ["Sato", "Takahashi", "Watanabe", "Ito", "Yamamoto", "Nakamura", "Kobayashi",
		"Kato", "Yoshida", "Matsumoto", "Inoue", "Kimura"],
	"korean": ["Kim", "Lee", "Park", "Choi", "Jung", "Kang", "Cho", "Yoon", "Jang", "Lim", "Han", "Seo"],
	"chinese": ["Wang", "Li", "Zhang", "Liu", "Chen", "Yang", "Huang", "Zhao", "Wu", "Zhou", "Xu", "Sun"],
	"mongolian": ["Batbayar", "Ganzorig", "Erdenebat", "Otgonbayar", "Purevdorj", "Tsogt",
		"Dorjsuren", "Lkhagva"],
	"sea": ["Pratama", "Saputra", "Wijaya", "Hidayat", "Santoso", "Reyes", "Cruz", "Bautista",
		"Villanueva", "Mendoza", "Garcia", "Ramos"],
	"turkish": ["Yılmaz", "Kaya", "Demir", "Şahin", "Çelik", "Arslan", "Doğan", "Aydın", "Öztürk",
		"Koç", "Kurt", "Aksoy"],
	"levant": ["Haddad", "Mansour", "Khalil", "Cohen", "Levi", "Mizrahi", "Saleh", "Nasser", "Peretz",
		"Farouk", "Azoulay", "Hamdan"],
}

## Original handles (single words / coined words). Combined with suffixes when exhausted.
const NICKNAMES: Array[String] = [
	"Sable", "Quill", "Ardent", "Basalt", "Cipher", "Ember", "Flint", "Grit", "Halcyon", "Jolt",
	"Kestrel", "Lumen", "Marrow", "Nettle", "Onyx", "Pike", "Quartz", "Rook", "Sorrel", "Thistle",
	"Umber", "Vane", "Wren", "Yarrow", "Zephyr", "Ashgrove", "Brine", "Cinder", "Dusk", "Fable",
	"Gale", "Hollow", "Inkwell", "Juniper", "Kiln", "Larch", "Mistral", "Nimbus", "Orrin", "Pebble",
	"Quiver", "Rime", "Slate", "Tinder", "Undertow", "Vesper", "Whisk", "Yonder", "Zinc", "Alder",
	"Bramble", "Coil", "Dapple", "Eddy", "Fern", "Gorse", "Heron", "Ibex", "Jasper", "Knoll",
	"Lark", "Moss", "Nook", "Ochre", "Plover", "Quarry", "Reed", "Shale", "Talon", "Urchin",
	"Velvet", "Wisp", "Yew", "Zither", "Anvil", "Beacon", "Cobble", "Driftwood", "Echo", "Ferrous",
	"Glint", "Hearth", "Isle", "Jigsaw", "Kelp", "Lattice", "Mantle", "Notch", "Oxbow", "Parley",
	"Quench", "Ripple", "Sprocket", "Tallow", "Updraft", "Vellum", "Waltz", "Yolk", "Zigzag", "Abacus",
	"Bobbin", "Cairn", "Dovetail", "Embark", "Fathom", "Gannet", "Hatchet", "Inlet", "Jetty", "Keel",
	"Loam", "Mallet", "Nimble", "Oakum", "Pylon", "Quoit", "Rivet", "Spindle", "Tarn", "Ulterior",
	"Vortice", "Wicket", "Yardarm", "Zircon", "Arbour", "Brisk", "Corvid", "Dirge", "Elver", "Frost",
	"Grackle", "Haze", "Ivory", "Jackdaw", "Kindle", "Lichen", "Murk", "Nightjar", "Opal", "Puffin",
	"Quagga", "Raven", "Siskin", "Tern", "Upland", "Verdigris", "Warbler", "Xylo", "Yukon", "Zebu",
	"Amber", "Bolt", "Crag", "Delve", "Ether", "Fuse", "Gravel", "Husk", "Iris", "Jinx",
	"Karst", "Lode", "Mire", "Nova", "Orbit", "Prism", "Quell", "Rust", "Scree", "Tundra",
	"Ursa", "Vigil", "Weld", "Yawl", "Zenith", "Aster", "Bracken", "Chisel", "Dross", "Eyrie",
	"Fjord", "Gusset", "Hinge", "Ingot", "Joist", "Kettle", "Lynchpin", "Mortar", "Nib", "Otter",
	"Piston", "Quayside", "Ratchet", "Sluice", "Trellis", "Umbra", "Valve", "Wharf", "Yearling", "Zodiac",
]
const NICKNAME_SUFFIXES: Array[String] = ["x", "o", "y", "ix", "er", "z"]

## Organisation name parts: place-like first word + noun. Two-word combinations only, which keeps
## them clear of real single-word organisation names.
const ORG_PLACES: Array[String] = [
	"Northbridge", "Saltmarsh", "Ironvale", "Crimson", "Atlas", "Halcyon", "Cobalt", "Granite",
	"Harbour", "Highmoor", "Kingsfold", "Larkspur", "Meridian", "Nightfall", "Oakridge", "Pinecrest",
	"Quarryside", "Redwater", "Silverline", "Stonegate", "Thornfield", "Umberlight", "Valewood",
	"Westmarch", "Amberly", "Blackwater", "Coldharbour", "Duskmere", "Eastwind", "Foxhollow",
	"Glasshouse", "Hollowpeak", "Juniper", "Kestrel", "Lowmoor", "Moonfield", "Newhaven", "Orchard",
]
const ORG_NOUNS: Array[String] = [
	"Vortex", "Lantern", "Union", "Drift", "Forge", "Comets", "Harriers", "Owls", "Ravens",
	"Collective", "Circuit", "Engine", "Tempest", "Monarchs", "Pilots", "Herons", "Anchors",
	"Pioneers", "Rangers", "Cartel", "Assembly", "Signal", "Meteors", "Kites", "Badgers", "Otters",
	"Lancers", "Gulls", "Stags", "Embers",
]
const ORG_STYLES: Array[String] = ["%s", "%s", "%s", "%s Esports", "%s Gaming", "Team %s"]

## Competition name words (original). International events: "<word> <EVENT_SUFFIX>".
const COMPETITION_WORDS: Array[String] = [
	"Apex", "Summit", "Meridian", "Zenith", "Solstice", "Equinox", "Horizon", "Vanguard", "Paragon",
	"Crown", "Keystone", "Pinnacle", "Aurora", "Northstar", "Tidewater", "Ironclad",
]
const EVENT_SUFFIXES: Array[String] = ["Masters", "Invitational", "Classic", "Championship"]
