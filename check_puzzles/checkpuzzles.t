#charset "us-ascii"

#ifdef __DEBUG

/*
 *   Simply put: this will play your game by wandering through your rooms.  It "cheats" by
 *   ensuring the player is self-lit and can carry everything w/o needing to
 *   pick-and-choose or have a bottomless bag to put things in.  It measures its progress
 *   by seeing if its "loot" (inventory) has grown AND how well it is doing on solving
 *   puzzles.
 *
 *   There are two options: quit wandering when the game won or go to every room
 *
 *   See the PuzzleSolution class as you will need that to solve the puzzles along the
 *   way!
 *
 */

#include "advlite.h"
#include "lookup.h"
#include <vector.h>


#define MAX_NOCHANGE 7   // if cannot make progress coming back multiple time, skip it


property weightCapacity;


// when create these, use transient so they survive/are immune to save/restore
class checkPuzzleState: object
    // see if this state is a winning state
    gameWon = nil    
    // see if this state is a losing (usually means dead) state
    gameLost = nil
    // puzzle objects that are still active
    puzzles = []
    // current score
    curScore = 0
    // inventory of this state
    inventory = []
    // directions left to go: nil if not yet populated, or done if empty list
    dirs = nil
    // game saved for this state
    gameSaved = nil
    // number of moves to this point
    moves = 0
    // number of times got here with no change
    nochangecount = 0
    // id of the room
    location = nil
    // constructor
    construct(locn?)
    {
        location = locn;
    }
    // save the state
    setstate(oldstate?)
    {
        if(oldstate != nil) {
            // copy these  over
            puzzles = oldstate.puzzles;
            nochangecount = oldstate.nochangecount;
            
            // but the rest is made current
    //        location = rm;
        }
        inventory = checkPuzzles.getInventory();
        moves = libGlobal.totalTurns;
        curScore = checkPuzzles.getScore();
//        savegame();
    }
    // exit with error if game cannot be saved
    savegame() {       
        if(gameSaved == nil)
            gameSaved = new TemporaryFile();
        try {
            saveGame(gameSaved);
        }
        catch (StorageServerError sse)
        {
            /* the save failed due to a storage server problem - explain */           
            DMsg(save failed on server, '<.parser>Failed, because of a problem
                accessing the storage server:
                <<makeSentence(sse.errMsg)>><./parser>');

            /* done */
            return;
        }
        catch (RuntimeError err)
        {
            /* the save failed - mention the problem */
            DMsg(save failed, '<.parser>Failed; your computer might be running
                low on disk space, or you might not have the necessary
                permissions to write this file.<./parser>');            
            
            /* done */
            return;
        }
    }
   
    // return true if restored game ok, else nil
    restoregame() {
        if(gameSaved == nil) {
            "<.p>### No save file created!<.p>";
            return nil;
        }
        try
        {
            /* restore the file */
            restoreGame(gameSaved);
        }
        catch (StorageServerError sse)
        {
            /* failed due to a storage server error - explain the problem */
            DMsg(restore failed on server,'<.parser>Failed, because of a problem
                accessing the storage server:
                <<makeSentence(sse.errMsg)>><./parser>');            

            /* indicate failure */
            return nil;
        }
        catch (RuntimeError err)
        {
            /* failed - check the error to see what went wrong */
            switch(err.errno_)
            {
            case 1201:
                /* not a saved state file */
                DMsg(restore invalid file, '<.parser>Failed: this is not a valid
                    saved position file.<./parser> ');                
                break;
                
            case 1202:
                /* saved by different game or different version */
                DMsg(restore invalid match, '<.parser>Failed: the file was not
                    saved by this story (or was saved by an incompatible version
                    of the story).<./parser> ');               
                break;
                
            case 1207:
                /* corrupted saved state file */
                DMsg(restore corrupted file, '<.parser>Failed: this saved state
                    file appears to be corrupted.  This can occur if the file
                    was modified by another program, or the file was copied
                    between computers in a non-binary transfer mode, or the
                    physical media storing the file were damaged.<./parser> ');                
                break;
                
            default:
                /* some other failure */
                DMsg(restore failed, '<.parser>Failed: the position could not be
                    restored.<./parser>');                
                break;
            }

            /* indicate failure */
            return nil;
        }
               
        /* set the appropriate restore-action code */
        PostRestoreObject.restoreCode = 2;  // user restore

        /* notify all PostRestoreObject instances */
        PostRestoreObject.classExec();

        /* Ensure the current actor is defined. */
        gActor = gActor ?? gPlayerChar;
        
        return true;
    }
    destroygame() {
        if(gameSaved != nil) {
            gameSaved.deleteFile();
            gameSaved = nil;
        }
    }
;    

transient checkPuzzles: object
        
    // Map of direction properties to their command names
    dirs = [
        &north -> 'north',
        &south -> 'south',
        &east -> 'east',
        &west -> 'west',
        &up -> 'up',
        &down -> 'down',
        &in -> 'in',
        &out -> 'out',
        &northeast -> 'northeast',
        &northwest -> 'northwest',
        &southeast -> 'southeast',
        &southwest -> 'southwest',
        &fore -> 'fore',
        &aft -> 'aft',
        &port -> 'port',
        &starboard -> 'starboard'
    ]
    
    // set when actively exploring
    isExploring = nil
    
    // set when we want to disable output
    disableOutput = nil
    // set when disable output but notice there is some
    haveOutput = nil
    
    // set when have game ending message
    gameOverMsg = nil
    // set if won the game!
    gameWon = nil
    
    // puzzle objects that are still active
    puzzles = []
    
    // track rooms that are visited -- even if restore earlier game, this still wins
    roomVisited = nil
    
    /*
     *   Execute a command string programmatically -- nil if a problem!
     */
    executeCommand(cmdStr)
    {
        if (cmdStr == nil || cmdStr == '')
            return nil;
        
        "<.p><b>> <<cmdStr>></b>\n";
        try {    
            // Use Parser.parse to execute the command
            Parser.parse(cmdStr);
            return true;
        } catch (Exception ex) {
            // Ignore parsing/execution errors - we want to continue exploring
        }
        return nil;
    }

    // see if game over
    isGameOver(gstate?) {
        
        if(gameOverMsg != nil || gameWon || gameLost)
            return true;
        
        if(gstate != nil) {
            if(gstate.gameWon) {
                gameOverMsg = 'You won!';
                gameWon = true;
                "\b<<gameOverMsg.toUpper()>>\b";
                return true;
            }
            if(gstate.gameLost) {
                gameOverMsg = 'You lost!';
                "\b<<gameOverMsg.toUpper()>>\b";
                gameLost = true;
                return true;
            }
            if(gstate.puzzles.length() == 0) {
                gameOverMsg = 'You ran out of puzzles!';
                "\b<<gameOverMsg.toUpper()>>\b";
                return true;
            }                
        }
        return nil;
    }
    
    resetGameOver(gstate?) {
        gameOverMsg = nil;
        gameWon = gameLost = nil;
        
        if(gstate != nil) {
            gstate.gameWon = gstate.gameLost = nil;
        }
    }

#if 0
    /*
     *   Helper function to find all rooms in the game
     */
    findAllRooms()
    {
        local rooms = [];
        local currentRoom = firstObj(Room);
        
        while (currentRoom != nil) {
            if (currentRoom.ofKind(Room) && currentRoom.name != nil && currentRoom.name != 'unknown') {
                rooms += currentRoom;
            }
            currentRoom = nextObj(currentRoom, Room);
        }
        return rooms;
    }
#endif

    getScore() {
        return (libGlobal.scoreObj == nil)? 0 : libGlobal.scoreObj.totalScore;
    }

    /*
     *   getExitDirs(room)
     *   
     *   Returns a list of directions
     */
    getExitDirs(room)
    {
        local exitRooms = [];
        local exits = [];
        local dest;
        
        // Check each standard direction property
        local dlist = dirs.keysToList();
        disableOutput = true;
        foreach (local dirProp in dlist) {
            dest = nil;
            haveOutput = nil;
            try {
                dest = room.(dirProp);
            } catch (Exception ex) {
                continue;
            }
            if (dest != nil && dataType(dest) == TypeObject &&
                                    (dest.ofKind(Room) || dest.ofKind(TravelConnector))) {
                if(exitRooms.indexOf(dest) == nil) {
                    exits += dirProp;
                    exitRooms += dest;
                }
            } else if (haveOutput && exits.indexOf(dirProp) == nil) {
                exits += dirProp;
            }
        }
        disableOutput = nil;
        return exits;
    }

    // get room contents
    getRoomContents(room) {
        return dropUnusable(room.notionalContents());
    }
    
    // get inventory
    getInventory() {
        return dropUnusable(gPlayerChar.notionalContents());
    }

    dropUnusable(lst) {
        local retlist = [];
        
        foreach(local item in lst) {
            if(item.isFixed || item.isDecoration || !item.isListed)
                continue;
            retlist += item;
        }
        return retlist;
    }
    
    // return the list in a random order
    randList(lst)
    {
        local retlst = [];
        local j;
        for(local i = lst.length(); i > 0; --i) {
            j = rand(i) + 1;
            retlst += lst[j];
            lst = lst.removeElementAt(j);
        }
        return retlst;
    }

    /*
     *   This runs through rooms until such time as score increases or puzzle solved or
     *   game won
     */
    checkAllRooms(oldstate)
    {
        local roomStatus = new transient LookupTable(200,200);
        
        local cont, gstate, exits, gstateCur, gdir, idx;
        local rmInfo, rm;
               
        local gameState = new transient Vector(200);
        gameState.append(oldstate);
        local doRestore = nil;
        
        while(gameState.length() > 0) {
            // get current state
            idx = gameState.length();
            gstate = gameState[idx];
            if(gstate.dirs != nil && gstate.dirs.length == 0) {
                // nothing more to do here, so drop it and move onto the next
                gameState.removeElementAt(-1);
                doRestore = true;
                continue;
            }
            if(doRestore) {
                doRestore = nil;
                gstate.restoregame();
                // but we do something cute which is to say a room has been visited.
                // that way, we can ensure we can go anywhere we have seen regardless
                // of the actual save game being restored... it's a bit of a hack
                foreach(rm in roomVisited.keysToList())
                {
                    rm.setSeen();
                    rm.visited = true;
                    rm.examined = true;
                }
                "\n--------\nResetting game back to location
                <<gstate.location.roomTitle>>\n--------\n";
            }
            resetGameOver(gstate);
            rm = gstate.location;
            roomVisited[rm] = true;
            // get inventory and room contents
            cont = getRoomContents(rm);
            // keeps the user apprised what is happening
            statusLine.showStatusLineDaemon();
            
            // always try to grab everything when enter a room
            if(cont.length() >  0) {
                executeCommand('take all');
                if(isGameOver()) {
                    if(gameLost) {
                        // well, this is a bad command
                        if(!executeCommand('undo')) {
                            "### ERROR trying to UNDO an adventure failure (death/loss)!\n";
                            abort;
                        }
                    }
                    else
                        return gstate;
                }
                // forced take is not a good idea...
//                local i2 = getInventory();
//                if(i2.length() - inv.length() < cont.length()) {
//                    // take all did not work -- so have to do some forced take
//                    foreach(local c2 in getRoomContents(rm)) {
//                        "--- Force take of <<c2.disambigName>>\n";
//                        c2.moveInto(gPlayerChar);
//                    }
//                }
            }
            // gets inventory and copies over puzzles, visits, ...
            gstateCur = new transient checkPuzzleState(rm);
            gstateCur.setstate(gstate);
            
            // see if any puzzles worth solving -- if so, we will be exiting after solving it
            local bestpz = nil, bestmovepz = nil, movelocn;
            foreach (local pz in gstate.puzzles) {
                // when
                if(!pz.when) continue;
                // during (indexWhich returns true if any compare is true, nil if all nil)
                if(pz.during != nil && valToList(pz.during).indexWhich({s:s.isHappening}) == nil) continue;
                // holding
                if(pz.holding != nil &&
                   valToList(pz.holding).indexWhich({x:!x.isHeldBy(gPlayerChar)})) continue;
                // absent from player 
                if(pz.absent != nil &&
                   valToList(pz.absent).indexWhich({x:x.isHeldBy(gPlayerChar)})) continue;

                // depending upon if everywhere or not
                if(pz.where == nil || 
                   valToList(pz.where).indexWhich({x:x.isOrIsIn(gLocation)})) {
                    // everywhere or in current location
                    // visible in room
                    if(pz.visible == nil ||
                       valToList(pz.visible).indexWhich({x:x.isIn(gLocation) &&
                           !x.isHeldBy(gPlayerChar)})) {
                        // absent from room
                        if(pz.absent == nil ||
                           valToList(pz.absent).indexWhich({x:!x.isOrIsIn(gLocation)})) {
                                // keep track of best one
                                if(bestpz == nil || bestpz.priority < pz.priority)
                                    bestpz = pz;                            
                        }
                    }
                } else {
                    // so we are not in current location but MAYBE still viable
                    foreach(local locn in valToList(pz.where)) {
                        if(!locn.visited) continue; // not visited yet, so cannot count it
                        // visible in room
                        if(pz.visible != nil &&
                           valToList(pz.visible).indexWhich({x:!x.isIn(locn)}))
                            continue;
                        // absent from player and room
                        if(pz.absent != nil &&
                           valToList(pz.absent).indexWhich({x:x.isOrIsIn(locn)}))
                            continue;
                        // keep track of best one
                        if(bestmovepz == nil || bestmovepz.priority < pz.priority) {
                            bestmovepz = pz;
                            movelocn = locn;
                        }
                    }
                }
            }
            if(bestpz) {
                // we are at the location where the puzzle is resolvable
                movelocn = nil;
            } else if (bestmovepz) {
                // we have what is necessary to make the puzzle resolvable
                bestpz = bestmovepz;
            }
            if(bestpz) {
                // we have a solution to persue
                // do we need to move to that location first?
                if(movelocn) {
                    // yep!
                    if(!executeCommand('GOTO <<movelocn.roomTitle>>')) {
                        "### ERROR with trying to move to room <<movelocn.roomTitle>>!\n";
                        abort;
                    }
                    if(isGameOver())
                        return nil;
                    rm = gLocation;
                }
                // now we run the commands in the list
                if(bestpz.cmdList != nil) {
                    foreach(local c in bestpz.cmdList) {
                        if(!executeCommand(c)) {
                            "### ERROR with trying to \"<<c>>\"!\n";
                            abort;
                        }                 
                    }
                }
                // see if outcome should be checked
                if(bestpz.outcome != '') {
                    movelocn = bestpz.outcome;
                    if(dataType(movelocn) == TypeObject) {
                        movelocn = [movelocn];
                    }
                    if(dataType(movelocn) == TypeList) {
                        // list of object(s) to be present
                        bestmovepz = true;
                        foreach(local obj in movelocn) {
                            if(obj.isIn(rm))
                                continue;
                            if(bestmovepz) {
                                "### Puzzle failed with objects expected but not
                                present:\n";
                                bestmovepz = nil;
                            }
                            "--- <<obj.disambigName>>\n";
                        }
                        if(!bestmovepz) {
                            "-----------------------------\b";
                            abort;
                        }
                    } else if(!movelocn) {  // conditional that should be true
                        "### Puzzle failed with outcome being nil; first cmd is:\n";
                        if(bestpz.cmdList != nil)
                            movelocn = bestpz.cmdList[1];
                        else
                            movelocn = '[NO COMMANDS]';
                        "### <<movelocn>>\n";
                        abort;
                    }
                }
                // update the status
                gstate.location = rm;
                gstate.setstate();
                movelocn = gstate.puzzles.indexWhich({x:x==bestpz});
                gstate.puzzles = gstate.puzzles.removeElementAt(movelocn);
                return gstate;
            }
                       
            // see if checking rooms for the first time
            if(gstate.dirs == nil) {
                exits = randList(getExitDirs(rm)); // purposely do this
                gameState[idx].dirs = exits;
                gameState[idx].savegame();
            }
            
            // time to bust a move on those rooms
            rmInfo = roomStatus[rm];  // will be nil if not defined yet        
            if(rmInfo == nil) {
                rmInfo = new LookupTable(4,4);  // directions from this room
                roomStatus[rm] = rmInfo;
            }

            // look at next exit for the current room we are in
            gdir = gameState[idx].dirs[1];
            gameState[idx].dirs = gameState[idx].dirs.sublist(2);
            
            gstate = rmInfo[gdir];
            if(gstate != nil) {
                if(gstateCur.curScore < gstate.curScore ||
                        gstate.nochangecount > MAX_NOCHANGE) {
                    continue;   // old had better score means skip this
                } else if(gstateCur.curScore == gstate.curScore) {
                    if(gstateCur.puzzles.length > gstate.puzzles.length) {
                        continue;   // old had better puzzle solving means skip this
                    } else if(gstateCur.puzzles.length == gstate.puzzles.length) {
                        // no change in puzzle count, so increase visits with no progress
                        gstateCur.nochangecount = gstate.nochangecount + 1;
                    } else {
                        gstateCur.nochangecount = 0;  // it is better now!
                    }
                }
            }            

            // now do the move
            if(!executeCommand(dirs[gdir])) {
                "### ERROR with trying to move in direction of <<dirs[gdir]>>!\n";
                abort;
            }
            if(isGameOver() && gameLost) {
                // well, this is a bad direction -- don't do THAT again
                doRestore = true;
                continue;
            }            
            gstateCur.location = gLocation;  // set new location
            gstateCur.setstate();
            rmInfo[gdir] = gstateCur;
            roomStatus[rm] = rmInfo;
            gameState.append(gstateCur);
            if(isGameOver())
                return gstateCur;
        }
        return nil;
    }

    /*
     *   checkPuzzles()
     *   
     */
    
    checkpuzzles()
    {
        local fname = 'checkPuzzles.txt';
        
        "---- Creating script/log <<fname>>\n";
        if(!aioSetLogFile(fname,LogTypeTranscript)) {
            "### Failed to open up log file \"<<fname>>\"!\b";
            return;
        }
                
        // initialize the system -- should probably do this during pre-init but can happen after restart
        puzzles = [];
        local obj;
        for (local pz = firstObj(PuzzleSolution); pz != nil; pz = nextObj(pz,PuzzleSolution)) {
            puzzles += pz;
        }
        if(puzzles.length() == 0) {
            "### No PuzzleSolution objects defined -- cannot proceed.\b";
            return;
        }

        // make the player super-human
        local olocn = gLocation;
        local olit = gPlayerChar.isLit;
        local oldBulkCapacity   = gPlayerChar.bulkCapacity;
        local oldMaxSingleBulk  = gPlayerChar.maxSingleBulk;
        local oldWeightCapacity = gPlayerChar.weightCapacity;
        
        gPlayerChar.isLit = true;
        gPlayerChar.bulkCapacity   = 65535;
        gPlayerChar.maxSingleBulk  = 65535;
        gPlayerChar.weightCapacity = 65535;

        // starting location is where ator is now anyway
        isExploring = true;
        disableOutput = gameOverMsg = gameWon = nil;
        local gstate = new transient checkPuzzleState(olocn);
        local gotostate = gameMain.fastGoTo;
        gameMain.fastGoTo = true;
        gstate.puzzles = puzzles;   // all puzzles active at start
        roomVisited = new transient LookupTable(200,200);

        executeCommand('L');    // look to get us started
        
        while(true) {
            "-------- New state is puzzles left <<gstate.puzzles.length()>> and score
            <<gstate.curScore()>>\n";
            local gstateNew = checkAllRooms(gstate);
            if(isGameOver(gstateNew)) {
                "\b==================================\n";
                "<<gameOverMsg>>\n==================================\n";
                break;
            }
            if(gstateNew == nil) {
                "### Ran out of game exploration with puzzle(s) unsolved (first cmd of each):\n";
                foreach(local pz in gstate.puzzles) {
                    if(pz.cmdList == nil)
                        "--- [NO COMMANDS]\n";
                    else
                        "--- <<pz.cmdList[1]>>\n";
                }
                "\b### The following rooms have not been visited (perhaps related):\n";
                for (local rm = firstObj(Room); rm != nil; rm = nextObj(rm,Room)) {
                    if(!rm.visited && rm.roomTitle != nil && rm.roomTitle != 'unknown')
                        "--- <<rm.roomTitle>>\n";
                }
                "<.p>";
                break;
            }
            gstate = gstateNew;
        }
        isExploring = nil;
        
        // close log
        "---- Closing script/log <<fname>>\n";
        aioSetLogFile(nil,LogTypeTranscript);
        gameMain.fastGoTo = gotostate;
        // restore player
        gPlayerChar.moveInto(olocn);
        gPlayerChar.isLit = olit;
        gPlayerChar.bulkCapacity   = oldBulkCapacity;
        gPlayerChar.maxSingleBulk  = oldMaxSingleBulk;
        gPlayerChar.weightCapacity = oldWeightCapacity;
    }

;   // end of gamePuzzle


    
/*
 *   Command to check game
 */

VerbRule(CheckPuzzles)
    'checkPuzzles'   // (|'-visitall' -> visitall)
    : VerbProduction
    action = CheckPuzzles
    verbPhrase = 'checkPuzzles'
;

DefineSystemAction(CheckPuzzles)
    execAction(cmd) {
        checkPuzzles.checkpuzzles();
    }
;

/*
 *   Have to mess with some of the code in order to collect the information we need to
 *   process things
 */

modify aioSay(txt)
{
    if(checkPuzzles.disableOutput)
        checkPuzzles.haveOutput = true;
    else
        replaced(txt);
}


modify Action
{
    turnSequence() {
        if(!checkPuzzles.disableOutput)
            inherited();
    }
}


// just in case we somehow end up here -- do not want it to actually end the game
modify finishGameMsg(msg,extra)
{
    local fmap = [ ftDeath -> 'You died!', ftFailure -> 'You failed!', ftGameOver -> 'Game Over!',
        ftVictory -> 'You won!' ];
    if(checkPuzzles.disableOutput)
        return; // do nothing if disabled
    if(checkPuzzles.isExploring) {
        if(fmap.isKeyPresent(msg) != nil) {
            if(msg == ftVictory)
                checkPuzzles.gameWon = true;
            else
                checkPuzzles.gameLost = true;
            msg = fmap[msg];
        } else if(dataType(msg) != TypeSString) {
            msg = 'Unknown ending!';
        }
        checkPuzzles.gameOverMsg = msg;
        "\b<<msg.toUpper()>>\b";
    } else
        replaced(msg,extra);
}

/*
 *   How to solve the puzzles
 */

class PuzzleSolution: object
    // commands (single-quoted strings) to execute to solve the puzzle (as needed)
    cmdList = nil
    // where can be Room, Region, or list thereof or nil if anywhere
    where = nil
    // what does the player need to have in their inventory: single object or list
    // if need to be wearing it, make it one of the commands
    holding = nil
    // what needs to be present in the room: single object or list
    visible = nil
    // what needs to be absent from the room (and player as well)
    absent = nil
    // what scene needs to be active (or any scene if nil)
    during = nil
    // what other conditions must hold (regular conditional expression)
    when = true
    // higher priority wins when all else is equal
    priority = 100
    // outcome can be expression OR object OR if a list, are the object(s) that must be in room
    // or on the player
    // use this hack for outcome that should not be tested
    outcome = ''
;


#endif  // __DEBUG
