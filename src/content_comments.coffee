fub = require './funcbag'
filter = require './filter'

class CmntIgnoreError extends Error
    constructor: (msg) ->
        @name = @constructor.name
        @message = "cmnt: #{msg}"
        Error.captureStackTrace this, @name

getSubmission = ->
    document.querySelector('td.subtext a[href^="item"]').href.match(/id=(\d+)/)[1]

class Cmnt
    @BUTTON_CLASS = 'hnbl_ToggleButton'
    @BUTTON_OPEN_LABEL = '[-]'
    @BUTTON_CLOSE_LABEL = '[+]'

    # submission is a id for this comment that represents its belonging
    # to a group.
    #
    # identNode is a dom node that contains <img> with a width attribute
    # that designates an ident as an indicator of child relation of a
    # comment.  If width == 0 the comment is a 'root' comment. There can be
    # any number or root comments.
    #
    # The list of identNode's can be obtained via 'td > img[height="1"]'
    # css selector.
    constructor: (@submission, @identNode) ->
        throw new Error 'invalid submission' unless @submission
        throw new Error 'node is not an image' unless @identNode?.nodeName == "IMG"

        @ident = @identNode.width

        # dude...
        @header = @identNode.parentNode.parentNode.querySelector 'span[class="comhead"]'
        throw new Error "cannot extract comment's header" unless @header
        @headerText = @header.innerText

        @body = @header.parentNode.parentNode.querySelector 'span[class="comment"]'
        throw new Error "cannot extract comment's body" unless @body
        if @body.innerText.match(/^\[(deleted|dead|flagkilled|flagged)\]$/) && @headerText == ""
            throw new CmntIgnoreError "deleted comment"

        link = (@header.querySelector 'a[href^="item?id="]') || (@header.querySelector 'a[href*="ycombinator.com/item?id="]')
        @messageID = (link.href.match /id=(\d+)/)[1] if link
        throw new Error "cannot extract comment's messageID for #{@headerText}" unless link

        @usernameElement = @header.querySelector 'a'
        @username = @usernameElement?.innerText
        throw new Error "cannot extract comment's username for #{@headerText}" unless @username

        @makeButton()

    makeButton: ->
        throw new Error 'button already exist' if @button # don't make it twice

        @button = document.createElement 'span'
        @button.className = Cmnt.BUTTON_CLASS

        t = document.createTextNode '?'
        @button.appendChild t
        @buttonOpen()

        # insert a button
        node = @header.firstChild
        @header.insertBefore @button, node
        @header.insertBefore (document.createTextNode ' '), node
#        console.log "cmnt: new button #{@headerText}"
        console.log "cmnt: new button"

    buttonOpen: ->
        throw new Error "button doesn't exist" unless @button
        @button.innerText = Cmnt.BUTTON_OPEN_LABEL
        @button.style.cursor = '-webkit-zoom-out'

    buttonClose: ->
        throw new Error "button doesn't exist" unless @button
        @button.innerText = Cmnt.BUTTON_CLOSE_LABEL
        @button.style.cursor = '-webkit-zoom-in'

    isOpen: ->
        throw new Error "button doesn't exist" unless @button
        @button.innerText == Cmnt.BUTTON_OPEN_LABEL

    close: ->
        @bodyHide()
        @buttonClose()

    open: ->
        @bodyHide false
        @buttonOpen()

    # Show if !hide.
    #
    # For 1 paragraph comments, a 'reply' link is a next sibling to
    # @body. All praise pg!
    bodyHide: (hide = true) ->
        state = if hide then "none" else ""

        reply = @body.nextSibling
        if reply?.nodeName == "P"
            @body.style.display = state
            reply.style.display = state
        else
            @body.style.display = state

    scroll: ->
        throw new Error "button doesn't exist" unless @button
        @button.scrollIntoView true


class FavCon
    @WIN_WIDTH = 200

    constructor: (favorites, @comments, @cursor) ->
        @users = {}
        @setFavorites favorites

        chrome.extension.sendMessage fub.Message.Creat('commentsGetContentsHTML', {}), (res) =>
            console.log 'favcon: got html'
            div = document.createElement 'div'
            document.body.appendChild div
            div.innerHTML = res.html

            @win = document.querySelector '#hnbl_favorites'
            @win.style.display = 'none'
            @setWinPos()

            @btnClose = document.querySelector '#hnbl_favoritesClose'
            @table = document.querySelector '#hnbl_favoritesUsers'

            @guiBind()

    setWinPos: ->
        @win.style.left = "#{window.innerWidth - FavCon.WIN_WIDTH - 50}px"

    setFavorites: (hash) ->
        @favorites = fub.val2key hash

    size: ->
        (Object.keys @users).length

    usersUpdate: (name, index) ->
        @users[name] = [] unless @users[name]
        @users[name].push index

    guiBind: ->
        @btnClose.addEventListener 'click', (event) =>
            @toggle()
        , false

        # recalculate window position
        window.addEventListener 'resize', (event) =>
            @setWinPos()
        , false

    fill: ->
        @addRow key, val for key, val of @users

    addRow: (name, comments) ->
        return unless name && comments

        row = document.createElement 'tr'

        username = document.createElement 'td'
        colorbox = document.createElement 'span'
        colorbox.style.display = 'block'
        colorbox.style.cursor = 'pointer'
        colorbox.appendChild (document.createTextNode name)
        colorbox.addEventListener 'click', (event) =>
            @cursor.findAndSet 1, (comment) ->
                comment.username == name
            , "no other #{name}'s comment found"
        , false
        username.appendChild colorbox

        unread = @makeTD (@getUnread name)
        unread.style.cursor = 'pointer'
        unread.addEventListener 'click', (event) =>
            @cursor.findAndSet 1, (comment) ->
                comment.username == name && comment.isOpen()
            , "no other expanded #{name}'s comment found"
        , false

        row.appendChild idx for idx in [username, unread, @makeTD comments.length]
        @table.appendChild row
        fub.Colour.paintBox colorbox, @favorites[name]

    makeTD: (val) ->
        e = document.createElement 'td'
        e.appendChild (document.createTextNode val)
        e

    getUnread: (name) ->
        return 0 unless @users[name]

        r = 0
        ++r for idx in @users[name] when @comments[idx].isOpen()
        r

    toggle: ->
        if @size() == 0
            console.log 'favcon: no favorite users here'
            return
        @win.style.display = if @win.style.display == '' then 'none' else ''


class Forum
    @COLLAPSE_STATUS = {
        unmodified: 'not collapsed'
        read: 'collapsed due to read'
        blacklist: 'collapsed due to blacklist'
    }

    constructor: (@comments, @memory, @cursor) ->
        throw new Error 'invalid comments array' unless @comments instanceof Array
        console.error "forum: memory isn't initialized" unless @memory
        console.error "forum: cursor isn't initialized" unless @cursor

        @favcon = new FavCon {}, @comments, @cursor

        # statistics
        @collapsed = 0

        chrome.extension.sendMessage fub.Message.extStorageGetAll(), (res) =>
#            console.log res
            f = new filter.FilterExact false
            f.blackSet res.Filters.username.join "\n"

            @favcon.setFavorites res.Favorites

            for unused, index in @comments
                @addEL index

                @paint index, f
                req = @collapse index, f
                req.addEventListener 'complete', (event) =>
                    console.log "forum: collapse oncomplete: index=#{event.detail.index}, status=#{event.detail.status}"
                    @updateTitle event.detail.index
                    @scrollToExpanded event.detail.index
                    @favconFill event.detail.index

    paint: (index, filter) ->
        comment = @comments[index]

        color = @favcon.favorites['@']
        if filter.match comment.username
            fub.Colour.paintBoxIn comment.usernameElement, color
        else
            return unless color = @favcon.favorites[comment.username]
            fub.Colour.paintBox comment.usernameElement, color
            @favcon.usersUpdate comment.username, index

        console.log "forum: paint: #{comment.username} in #{color}"

    addEL: (index) ->
        comment = @comments[index]
        comment.button.addEventListener 'click', (event) =>
            if event.ctrlKey
                # just select a clicked button
                @cursor.moveTo index
            else if event.altKey
                # just toggle without moving a cursor
                @subthreadToggle index
            else
                @subthreadToggle index
                # and select a clicked button
                @cursor.moveTo index
        , false

    # Collapse or expand index comment and all its children.
    subthreadToggle: (index) ->
        comment = @comments[index]
        children = @subthreadGet index
        if comment.isOpen()
            idx.close() for idx in children
        else
            idx.open() for idx in children

    commentToggle: ->
        comment = @cursor.getCurrentComment()
        if comment.isOpen() then comment.close() else comment.open()

    commentSubtreadToggle: ->
        @subthreadToggle @cursor.current

    # Return an array with an index comment & all its children.
    subthreadGet: (index) ->
        comment = @comments?[index]
        throw new Error "invalid index #{index}" unless comment

        # collect children
        children = [comment]
        idx = index + 1

        ident = comment.ident
        while @comments[idx]?.ident > ident
            children.push @comments[idx]
            idx += 1

        console.log "forum: #{comment.messageID} children: #{children.length-1}"
        children


    # Collapse comment if it is in indexdb. Collapse exactly 1 comment,
    # don't touch its children.
    collapse: (index, filter) ->
        return unless @memory

        comment = @comments[index]
        req = comment.button # object for event firing

        @memory.exist comment.messageID, (exists) =>
            if exists
                comment.close()
                @collapsed += 1
                event = new CustomEvent 'complete', {
                    detail: {
                        index: index
                        status: Forum.COLLAPSE_STATUS.read
                    }
                }
                req.dispatchEvent event
            else
                @memorize comment, (id) ->
                    status = Forum.COLLAPSE_STATUS.unmodified
                    if filter.match comment.username
                        comment.close()
                        @collapsed += 1
                        status = Forum.COLLAPSE_STATUS.blacklist

                    event = new CustomEvent 'complete', {
                        detail: {
                            index: index
                            status: status
                        }
                    }
                    req.dispatchEvent event

        req

    # Update icon title via sending a message to bg.js.
    updateTitle: (index) ->
        if index == @comments.length-1
            chrome.extension.sendMessage fub.Message.Creat('statComments', {
                collapsed: @collapsed
                total: @comments.length
            })

    # Scroll to 1st expanded comment, if possible.
    scrollToExpanded: (index) ->
        @cursor.findExpanded(1, false) if index == @comments.length-1

    # Add favorites to a favcon window
    favconFill: (index) ->
        return unless index == @comments.length-1 && @favcon.size() > 0
        @favcon.fill()
        @favcon.toggle()

    # Add comment to indexeddb.
    memorize: (comment, nextCallback) ->
        return unless @memory

        @memory.add {
            mid: comment.messageID
            username: comment.username
            submission: comment.submission
        }, nextCallback


class Memory
    @DB_NAME = 'hndl_memory'
    @DB_VERSION = 1
    @DB_STORE_COMMENTS = 'comments'

    constructor: (nextCallback) ->
        memory = this
        @db = null # database connection

        req = window.indexedDB.open Memory.DB_NAME
        req.onerror = (event) ->
            # how to test this?
            console.error "memory: db error: #{event.target.error}"
            nextCallback null if nextCallback?

        req.onupgradeneeded = (event) =>
            @db = req.result
            console.log "memory: db upgrade required"

            obj_store = @db.createObjectStore Memory.DB_STORE_COMMENTS, {keyPath: 'mid'}
            obj_store.createIndex 'username', 'username', {unique: false}
            obj_store.createIndex 'submission', 'submission', {unique: false}

            event.target.transaction.oncomplete = (event) ->
                console.log "memory: db upgrade completed: #{Memory.DB_NAME} v. #{Memory.DB_VERSION}"

        req.onsuccess = (event) =>
            @db = req.result

            # generic handler for all errors
            @db.onerror = (event) ->
                console.error "memory: db error: #{event.target.errorCode}"

            console.log 'memory: db opened'
            nextCallback memory if nextCallback?

    add: (object, nextCallback) ->
        t = @db.transaction [Memory.DB_STORE_COMMENTS], "readwrite"
        os = t.objectStore Memory.DB_STORE_COMMENTS
        req = os.put object
        req.onsuccess = ->
            console.log "memory: added #{object.mid} (#{object.username})"
            nextCallback object.mid if nextCallback?

    exist: (mid, nextCallback) ->
        t = @db.transaction [Memory.DB_STORE_COMMENTS], "readonly"
        os = t.objectStore Memory.DB_STORE_COMMENTS
        req = os.get mid
        req.onsuccess = (event) ->
            if event.target.result
                console.log "memory: #{mid} exists: #{req.result.username}"
                nextCallback true if nextCallback?
            else
                console.log "memory: no #{mid}"
                nextCallback false if nextCallback?


class CCursor
    constructor: (@comments) ->
        throw new Error 'invalid comments array' unless @comments instanceof Array

        # indices
        @prev = null
        @current = null

        # set cursor at first comment
        @move 42

    setAt: (commentIndex) ->
        comment = @comments[commentIndex]
        new Error 'ccursor: invalid commentIndex' unless comment?.button

        prev = @comments[@prev]
        @markAsSeen prev if prev?
        @markAsCurrent comment

        @current = commentIndex

    # From current point to any valid
    moveTo: (commentIndex) ->
        @prev = @current
        @setAt commentIndex

    getCurrentComment: ->
        @current = 0 unless @current?
        @comments[@current]

    markAsSeen: (comment) ->
        new Error 'ccursor: invalid comment' unless comment?.button

        comment.button.style.color = 'white'
        comment.button.style.background = '#ff00ff'

    markAsCurrent: (comment) ->
        new Error 'ccursor: invalid comment' unless comment?.button

        comment.button.style.color = 'white'
        comment.button.style.background = '#ff6600'

    # step is -1 or 1, -10 or 10, etc.
    move: (step) ->
        step = 1 unless step?
        @prev = @current

        if @current? then @current += step else @current = 0

        @current = 0 if @current >= @comments.length
        @current = @comments.length-1 if @current < 0

        @setAt @current
        @comments[@current].scroll()

    # direction is -1 or 1
    #
    # condition is a function that take 1 parameter (comment) & returns
    # true if comment meets some expectations, or false otherwize.
    #
    # log_message is a string that will be printed to console.log.
    findAndSet: (direction, condition, log_message, start_from_next = true) ->
        if @current? then start = @current else start = 0
        direction = 1 unless direction?

        itmax = @comments.length-1
        itcur = 0
        if start_from_next then pos = start + direction else pos = start

        while itcur < itmax
            pos = 0 if pos >= @comments.length
            pos = @comments.length-1 if pos < 0

            comment = @comments[pos]
            if condition(comment)
                @prev = start
                @setAt pos
                comment.scroll()
                return

            pos += direction
            itcur += 1

        console.log "cursor: BEEP, #{log_message}"

    # direction is -1 or 1
    findExpanded: (direction, start_from_next = true) ->
        @findAndSet direction, (comment) ->
            comment.isOpen()
        , "no expanded comments found", start_from_next

    # direction is -1 or 1
    findRoot: (direction) ->
        @findAndSet direction, (comment) ->
            comment.ident == 0
        , "no other root comments found"

    # direction is -1 or 1
    findSameLevel: (direction) ->
        @findAndSet direction, (comment) =>
            comment.ident == @comments[@current].ident
        , "no other comments on this level found"

    # direction is -1 or 1
    findSameUsername: (direction) ->
        @findAndSet direction, (comment) =>
            comment.username == @comments[@current].username
        , "no other comments of this user found"


class Keyboard
    @IGNORED_ELEMENTS = ['INPUT', 'TEXTAREA']

    constructor: (@forum) ->
        @keymap = {
            '75': [@forum.cursor, 'move', -1] # 'k' prev comment
            '74': [@forum.cursor, 'move', 1] # 'j' next
            '76': [@forum.cursor, 'findSameUsername', 1] # 'l' jump to current user's next comment
            '72': [@forum.cursor, 'findSameUsername', -1] # 'h' jump to current user's prev comment
            '188': [@forum.cursor, 'findExpanded', -1] # ',' prev unread comment
            '190': [@forum.cursor, 'findExpanded', 1] # '.' next unread
            '222': [@forum, 'commentToggle'] # 'single quote' collapse/expand current comment
            '186': [@forum, 'commentSubtreadToggle'] # ';' collapse/expand current subthread
            '221': [@forum.cursor, 'findRoot', 1] # ']' jump to next root comment
            '219': [@forum.cursor, 'findRoot', -1] # '[' jump to prev root comment
            'S-221': [@forum.cursor, 'findSameLevel', 1] # ']' jump to next comment on the same level
            'S-219': [@forum.cursor, 'findSameLevel', -1] # '[' jump to prev comment on the same level
            '67': [@forum.favcon, 'toggle'] # 'c' show/hide favorites
        }
        @addEL()

    addEL: ->
        document.body.addEventListener 'keydown', (event) =>
            return unless @isValidElement event?.target
            @keycode2command event.keyCode, event.shiftKey
        , false

    isValidElement: (element) ->
        return false if Keyboard.IGNORED_ELEMENTS.indexOf(element?.nodeName) != -1
        true

    keycode2command: (keycode, shift) ->
        key = keycode?.toString()
        key = "S-#{key}" if shift

        if key of @keymap
            object = @keymap[key][0]
            method = @keymap[key][1]
            args = @keymap[key][2..-1]
            console.log "keyboard: #{@keymap[key]}"

            object[method].apply(object, args)
        else
            console.error "keyboard: keycode #{key} isn't assosiated with a command"


# Main

sub_id = getSubmission()
throw new Error 'cannot get a submission id for this page' unless sub_id
images = document.querySelectorAll('td > img[height="1"]')
console.log "images.length = #{images.length}"
if images.length == 0
    console.error '0 comments?'
    chrome.extension.sendMessage fub.Message.Creat('statComments', {
        collapsed: 0
        total: images.length
    })
    return

# grab comments
comments = []
for idx, index in images
    try
        comments.push new Cmnt(sub_id, idx)
    catch e
        if e instanceof CmntIgnoreError
            console.log "Ignoring comment #{index}: #{e.message}"
        else
            throw e

# make gui
cursor = new CCursor comments
new Memory (memory) ->
    forum = new Forum(comments, memory, cursor)
    new Keyboard forum
