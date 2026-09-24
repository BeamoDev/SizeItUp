--!strict

-- Whole visible object height in meters.
--
-- Sizing rules:
--  • Aircraft use published/model-specific overall heights where possible.
--  • Vehicles use typical overall roof/top height.
--  • Ships use approximate keel-to-highest-visible-point height.
--  • Furniture/appliances use typical household/commercial dimensions.
--  • Animals use approximate whole standing height to the top of the head/body,
--    rather than body length or shoulder height unless that is the natural visible height.
--  • Balls and very small objects use their real diameter/thickness.
--
-- These are representative per-TYPE real-world figures, not measurements of the
-- exact Roblox meshes. Override individual assets with a numeric HeightMeters
-- attribute on the ORIGINAL ServerStorage.Objects child if necessary.
--
-- IMPORTANT:
-- Some real objects are smaller than 0.1m, so the guessing system should support
-- decimal values below 0.1m rather than clamping everything to 0.1m.
--
-- These answers are never copied into replicated visual templates.
-- ObjectVisual first measures visible geometry and normalizes every template to one stud high; PreviewController
-- then multiplies the public reference by this value. Original import scale therefore has no gameplay meaning.

return table.freeze({

	----------------------------------------------------------------
	-- AIRCRAFT
	-- Overall height: ground/wheels to highest point.
	----------------------------------------------------------------

	Airbus330 = 16.8, -- Airbus A330-300
	Boeing737 = 12.5, -- Boeing 737-800
	Cessna = 4, -- Cessna 172
	F16 = 4.9, -- F-16 Fighting Falcon
	Helicopter = 3.5, -- Typical civilian/light helicopter
	OldPlane = 3.0, -- Typical small vintage propeller aircraft
	Blimp = 17.5, -- Goodyear-class blimp


	----------------------------------------------------------------
	-- SHIPS / BOATS
	-- Approximate keel/bottom to highest visible point.
	----------------------------------------------------------------

	CargoShip = 40,
	Cruise2 = 55,
	CruiseShip = 60,
	SailBoat = 12, -- Including mast
	Yacht = 6,
	SpeedBoat = 1.8,


	----------------------------------------------------------------
	-- LAND VEHICLES / MACHINES
	----------------------------------------------------------------

	Ambulance = 2.9,
	Bus = 3.2,
	SchoolBus = 3.3,

	Car2 = 1.5,
	Car3 = 1.5,
	Car4 = 1.5,
	Car5 = 1.5,
	Car6 = 1.5,

	Firetruck = 3.4,
	Humvee = 1.85,
	MonsterTruck = 3.5,

	PoliceCar = 1.5,
	Taxi = 1.5,

	Tank = 2.4, -- Approx. M1 Abrams turret height
	Truck = 3.8,
	Van = 2.2,

	ShippingContainer = 2.59, -- Standard ISO container

	Mortar = 1.0, -- Typical assembled infantry mortar


	----------------------------------------------------------------
	-- STRUCTURES / PLANTS
	----------------------------------------------------------------

	FerrisWheel = 50, -- Typical medium-large Ferris wheel

	Tent = 1.8,

	OakTree = 20,
	PalmTree = 12,
	Tree = 10,

	Plants = 0.6, -- Generic medium house/garden plant
	PlantPot = 0.5, -- Medium-large potted plant including plant/pot asset
	Grass = 0.1,


	----------------------------------------------------------------
	-- FURNITURE / HOUSEHOLD
	----------------------------------------------------------------

	Armchair2 = 0.95,
	SingleArmChair = 0.9,

	Chair = 0.9,
	Chair_PC = 1.1,

	ClockShelf = 1.8,

	Closet = 2.0,
	Wardrobe = 1.9,

	Computer = 0.5, -- Desktop monitor + stand

	DoubleBed = 0.9, -- Including typical headboard
	SingleBed = 0.8,

	DoubleCouch = 0.85,
	TripleCouch = 0.9,

	ExerciseBike = 1.3,

	Fridge = 1.8,

	Guitar = 1.0,

	Microwave = 0.30,

	Nightstand = 0.6,

	Sink = 0.9,

	Table = 0.75,

	Toilet = 0.8,

	Crate = 0.7,

	Tires = 0.65, -- Typical passenger-car tyre diameter

	Target = 1.5, -- Target + stand


	----------------------------------------------------------------
	-- ANIMALS
	-- Approximate natural standing / visible height.
	----------------------------------------------------------------

	Bird = 0.20,

	Chicken = 0.45,

	Deer = 1.5, -- Approx. adult deer to head top

	Dog = 0.6, -- Generic medium-large dog

	Fish = 0.20,

	Horse = 2.2, -- Ground to head/ear top; withers alone are ~1.6-1.7m

	Lizard = 0.08,

	Monkey = 0.6,

	Mouse = 0.08,

	Penguin = 0.9, -- King penguin-ish scale

	Snake = 0.05, -- Body height/thickness when on ground

	Squid = 0.4,

	Tiger = 1.2, -- Approx. standing animal to head top


	----------------------------------------------------------------
	-- SPORTS / SMALL OBJECTS
	----------------------------------------------------------------

	Basketball = 0.24,

	Football = 0.22,

	HockeyPuck = 0.025,

	TennisBall = 0.067,


	----------------------------------------------------------------
	-- EXPANDED HOUSEHOLD / PROP LIST
	----------------------------------------------------------------

	Bed = 0.85,

	Bottle = 0.25,

	Camera = 0.10,

	Chainsaw = 0.30,

	Chest = 0.5,

	Coffee = 0.12, -- Mug / takeaway cup

	CoffeeTable = 0.45,

	Couch = 0.85,

	Counter = 0.9,

	Desk = 0.75,

	Door = 2.0,

	Doublewardrobe = 2.0,

	Dumbbell = 0.20,
	Dumbell2 = 0.20,

	DummyYellow = 1.75,

	Flower = 0.35,

	FoldedClothes = 0.20,

	FrameDoor = 2.1,

	FruitBowl = 0.20,

	Glass = 0.14,

	Jacket = 0.70,

	Ketchup = 0.25,

	Lamp = 0.50,

	Microwave2 = 0.30,

	Piano = 1.2, -- Typical upright piano

	Picture = 0.60,

	Plunger = 0.55,

	Rack = 1.8,

	-- This is asset-specific and does not correspond to a standard real-world object.
	-- Keep 3m unless the mesh represents something identifiable.
	Scene = 3.0,

	Shelf = 1.8,

	SideLamp = 0.60,

	Sofa = 0.85,

	Speaker = 0.80,

	Stool = 0.65,

	TV = 0.60,

	WashingMachine = 0.85,

	Weights = 0.30,


	----------------------------------------------------------------
	-- PEOPLE / PETS
	----------------------------------------------------------------

	Cat = 0.30, -- Ground to upper body/head area

	Human = 1.75, -- Representative adult height
})
