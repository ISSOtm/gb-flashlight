
.PHONY: all clean rebuild  $(OBJDIR)/build_date.o
.SUFFIXES:


FillValue = 0xFF

ROMVersion = 1
DebugMode = 1

GameID = FLSH
GameTitle = FLASHLIGHT
# Licensed by Homebrew (lel)
NewLicensee = HB
OldLicensee = 0x33 # SGB compat and all that
# ROM
MBCType = 0x00
# ROM size is automatic
SRAMSize = 0x00


BINDIR  := bin
OBJDIR  := obj

RGBASM  := rgbasm
RGBLINK := rgblink
RGBFIX  := rgbfix
IMG2BIN := tools/img2bin.py

ASFLAGS := -E -h -p 0xFF
LDFLAGS := -p 0xFF
FXFLAGS := -jv -i $(GameID) -k $(NewLicensee) -l $(OldLicensee) -m $(MBCType) -n $(ROMVersion) -p $(FillValue) -r $(SRAMSize) -t $(GameTitle)


# Default target: build the ROM
all: $(BINDIR)/flashlight.gb

# Clean temp and bin files
clean:
	-rm -rf $(BINDIR)
	-rm -rf $(OBJDIR)


$(BINDIR)/flashlight.gb: obj/flashlight.o
	@mkdir -p $(BINDIR)

	$(RGBLINK) $(LDFLAGS) -o $@ -m $(@:.gb=.map) -n $(@:.gb=.sym) $^
	$(RGBFIX) $(FXFLAGS) $@

$(OBJDIR)/%.o: %.asm
	@mkdir -p $(OBJDIR)
	$(RGBASM) $(ASFLAGS) -o $@ $<
