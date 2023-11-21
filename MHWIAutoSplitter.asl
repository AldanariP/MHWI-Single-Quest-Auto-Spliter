// AutoSplitter script for Monster Hunter World: Iceborne by Aldanari
// This is an edited version for single quest run of the full game script by MoonBunnie, JalBagel, GreenSpeed : https://github.com/MoonBunnie/Monster-Hunter-World-Iceborne-AutoSplitter
// Inspired by Lyuha's Auto Splitter : https://github.com/lyuha/MHW-split
// And added adresses found on HunterPie github : https://github.com/HunterPie/HunterPie/blob/main/HunterPie/Address/MonsterHunterWorld.421631.map

//Supports v15.10+
state("MonsterHunterWorld"){}

startup {
  //Signatures for Base Pointer scans  
  vars.scanTargets = new Dictionary<string, SigScanTarget>();
  vars.scanTargets.Add("sMhGUI", new SigScanTarget(3, "48 8B 05 ?? ?? ?? ?? 0F 28 74 24 40 48 8B B4 24 ?? ?? ?? ?? 8B 98"));
  vars.scanTargets.Add("sQuest", new SigScanTarget(7, "48 83 EC 48 48 8B 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 3C 01 0F 84 E0 00 00 00 48 8B 0D ?? ?? ?? ?? E8"));
  vars.scanTargets.Add("sMhArea", new SigScanTarget(3, "48 8B 05 ?? ?? ?? ?? 0F B6 80 EB D2 00 00 C3"));
  
  //Settings
  settings.Add("closeReset", true, "Automaticly reset the timer when going back to town");
  
  //Force Game Time
  timer.CurrentTimingMethod = TimingMethod.GameTime;
  vars.timerModel = new TimerModel { CurrentState = timer };
}

init {
  //Initialize Rescan Params
  vars.scanErrors = 9999;
  vars.waitCycles = 0;
  
  //Initialize Base Pointer dictionary
  vars.basePointers = new Dictionary<string, IntPtr>();
  foreach (KeyValuePair<string, SigScanTarget> entry in vars.scanTargets) {
    vars.basePointers.Add(entry.Key, IntPtr.Zero);
  }
  
  //Define deferred init function, to support patch 15.11.01+ which introduced exe packing
  vars.init = (Func<bool>)(() => {
    if(vars.scanErrors == 0) { return true;} //Return true if init successful
    if(vars.waitCycles > 0 && vars.scanErrors > 0) { //Wait until next scan
      vars.waitCycles--;
      return false;
    }
    
    //Scan for Base Pointers
    vars.scanErrors = 0;
    foreach (KeyValuePair<string, SigScanTarget> entry in vars.scanTargets) {
      //Skip if already found
      if(vars.basePointers[entry.Key] != IntPtr.Zero) { continue;}
      
      var found = false;
      foreach (var page in memory.MemoryPages(true)) {
        //Skip pages outside of exe module
        if ((long)page.BaseAddress < (long)modules.First().BaseAddress || (long)page.BaseAddress > (long)modules.First().BaseAddress + modules.First().ModuleMemorySize) { continue;}
        
        //Get first scan result
        var scanner = new SignatureScanner(game, page.BaseAddress, (int)page.RegionSize);
        var ptr = scanner.Scan(entry.Value, 0x1);
        if (ptr != IntPtr.Zero) {
          vars.basePointers[entry.Key] = ptr + 0x4 + memory.ReadValue<int>(ptr);
          found = true;
          break;
        }
      }
      if (!found) { vars.scanErrors++;} //count remaining missing pointers
    }
    
    //finish init if all scans successful
    if (vars.scanErrors == 0) {
      //Setup Memory Watchers
      vars.loadDisplayState = new MemoryWatcher<byte>(new DeepPointer(vars.basePointers["sMhGUI"], 0x13F28, 0x1D04));
      vars.activeQuestId = new MemoryWatcher<int>(new DeepPointer(vars.basePointers["sQuest"], 0x4C));
      vars.activeQuestStatus = new MemoryWatcher<int>(new DeepPointer(vars.basePointers["sQuest"], 0x54));
      vars.areaStageId = new MemoryWatcher<int>(new DeepPointer(vars.basePointers["sMhArea"], 0x8058, 0xCC));
      
      //Register Watchers
      vars.watchers = new MemoryWatcherList() {
        vars.loadDisplayState,
        vars.activeQuestId,
        vars.activeQuestStatus,
        vars.areaStageId
      };
      return true;
    }
    
    vars.waitCycles = 300; //set delay until next scan
    return false;
  });
}

update {
  //Perform updates only if init successful
  if(vars.init()){ 
    vars.watchers.UpdateAll(game);
    print("Closed Reset : " + settings["closeReset"] + "  Active ID : " + vars.activeQuestId.Current + "  Reset? : " + (settings["closeReset"] && vars.activeQuestId.Current == -1 && vars.activeQuestId.Old != -1));
  } else {
    return false;
  }
}

start {
  // If there is an active quest & not in town & loading has ended
  return vars.activeQuestId.Current != -1 && vars.areaStageId.Current != 0 && vars.loadDisplayState.Current == 0 && vars.loadDisplayState.Old != 0;
}

split {
  // If quest is complete (does not currenlty support multiple split for multiple monsters hunt quest)
  return vars.activeQuestStatus.Current == 3 && vars.activeQuestStatus.Old == 2;
}

reset {
  // If quest was running & it has been abandoned, return to HQ or failed
  // Or automaticly if the quest as been completed and returned to town, if corresponding setting as been checked
  if (settings["closeReset"] && vars.activeQuestId.Current == -1 && vars.activeQuestId.Old != -1) vars.timerModel.Reset();
  return (vars.activeQuestStatus.Old == 2 && (vars.activeQuestStatus.Current == 5 || vars.activeQuestStatus.Current == 6 || vars.activeQuestStatus.Current == 7));
}