on run arguments
    set packagePath to item 1 of arguments
    do shell script "/usr/sbin/installer -pkg " & quoted form of packagePath & " -target /" with administrator privileges
end run
