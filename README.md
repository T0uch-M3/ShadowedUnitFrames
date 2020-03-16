# ShadowedUnitFrames

Made by <a href="https://www.wowace.com/projects/shadowed-unit-frames">shadowed103</a> and backported to tbc by <a href="https://github.com/Aviana">Aviana</a>, I'll try to add some stuff to it from time to time (not a serious project).

# For mob health display
-Make sure you're not having another addon that collect mobs data, like MobHealth(2,3), or another version of MobInfo, or this might not works.</br>
-Get MobInfo for <a href="http://www.mediafire.com/file/fmes0um4kyxiou9/MobInfo2_3_61.zip/file">here</a> and MobInfo Database from <a href="http://www.mediafire.com/file/70q6whaszdi5eqp/MobInfo2_Database.3-61.zip/file">here</a>
</br>-After extracting MobInfo extract the .lua file inside the database.zip into MobInfo2 folder "theGameFolder>Interface>AddOns>MobInfo2>MI2_Import.lua"
</br>-Inside the game, open the MobInfo addon, go to database tab and make sure the first 3 values are set to "0" if not clear them out with "Delete Database" then "Start the import".

</br><b>Note:</b> </br>The implementation is not perfect, currently it only works with the tag "curmaxhp", from that tag it's easy make it work on the rest, just open tag.lua and change it as you like, due to low prio, this will be fixed another time.
</br></br>Another thing, this implementation will only display the HP of mobs that CAN attack you, so you won't see the HP of friendly NPCs, tho you can see it through MobInfo tooltip (weird right!), I just couldn't figure out how to do it on the UF.
