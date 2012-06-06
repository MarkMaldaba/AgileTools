// Add $().reverse()
jQuery.fn.reverse = [].reverse;

/**
 * jQuery Buglist widget
 */
$.widget("agile.buglist", {

    /**
     * Default options
     */
    options: {
        order: false,
        sortable: true,
        itemTemplate: "#bug_item_template",
        connectWith: false,
    },
    /**
     * Initialize the widget
     */
    _create: function()
    {
        this._items = {};
        this._lastSearch = null;
        this._searchIndex = 0;
        this.element.addClass("buglist");

        this.element.sortable({
            connectWith: this.options.connectWith,
            stop: $.proxy(this, "_onSortStop"),
            receive: $.proxy(this, "_onSortReceive"),
            update: $.proxy(this, "_onSortUpdate"),
        });

        $.Widget.prototype._create.apply( this, arguments );
    },

    /**
     * Destroy the widget
     */
    destroy: function()
    {
        this.clear();
        this.element.removeClass("buglist");
        this.element.sortable("destroy");
        $.Widget.prototype.destroy.apply(this);
    },

    clear: function()
    {
        this.element.children(":agile-blitem").blitem("destroy").remove();
        this._items = {};
    },

    _onParentReconnect: function(newConnection)
    {
        this._setOption("connectWith", newConnection);
    },

    /**
     * jQuery widget options setting method
     */
    _setOption: function(key, value)
    {
        $.Widget.prototype._setOption.apply( this, arguments );
        if (key == "connectWith") {
            this.element.sortable("option", "connectWith", value);
        }
    },

    /**
     * Add bug
     * @param bug: Bug object as received from the WS api
     * @returns: jQuery object of the created blitem
     */
    addBug: function(bug)
    {
        var element = $(this.options.itemTemplate)
            .clone().attr("id", null)
            .blitem({
                bug: bug,
                _buglist: this,
            });
        var item = element.data("blitem");
        this._items[bug.id] = item;
        this._placeItemElement(element);
        return element;
    },

    _placeItemElement: function(element)
    {
        var bug = element.blitem("bug");
        var blocked = this._items[bug.blocks[0]];
        if (blocked) {
            blocked.addDepends(element);
        } else if (this.element.find(":agile-blitem").index(element) == -1) {
            var place = null;
            if (this.options.order) {
                var order = this.options.order;
                this.element.children(":agile-blitem").each(function() {
                    var tmp = $(this).blitem("bug");
                    if (tmp[order] > bug[order]) {
                        place = $(this);
                        return false;
                    }
                });
            }
            if (place) {
                place.before(element);
            } else {
                this.element.append(element);
            }
        }
        for (var i = 0; i < bug.depends_on.length; i++) {
            var depend = this._items[bug.depends_on[i]];
            if (depend) {
                element.blitem("addDepends", depend.element);
            }
        }
    },

    _onSortStop: function(ev, ui)
    {
        if (this.element.find(":agile-blitem").index(ui.item) == -1) {
            // remove item if it was moved to other list
            delete this._items[ui.item.blitem("bug").id];
        }
    },

    _onSortUpdate: function(ev, ui)
    {
        var reverse = false;
        var trigger = "receive";
        var self = this;

        if (!ui.sender) {
            if (this.element.index(ui.item)) {
                trigger = "move";
            } else {
                trigger = "remove";
            }
            /* TODO: This revese stuff is a bit hackish
             * When re-ordering the items inside single list, the backend
             * method Pool.add_bug() needs to be called in reverse order 
             * starting from the lowest dependency included in the block.
             * Otherwise the order is not updated correctly
             */
            reverse = ui.position.top > ui.originalPosition.top;
            // Bounce the item to indicate where it ended
            ui.item.blitem("bounce");
        }
        
        var movedItems = ui.item.add(":agile-blitem", ui.item);
        if (reverse) movedItems = movedItems.reverse();
        movedItems.each(function() {
            var index = self.element.find(":agile-blitem").index(this);
            self._trigger(trigger, ev, {
                bug: $(this).blitem("bug"),
                index: index,
            });
        });
    },

    _onSortReceive: function(ev, ui)
    {
        this._placeItemElement(ui.item);
        var item = ui.item.data("blitem");
        item._setOption("_buglist", this);
        this._items[item.options.bug.id] = item;
    },
    search: function(text)
    {
        this.element.find(":agile-blitem").blitem("highlight", false);
        if (this._lastSearch == text) {
            this._searchIndex++;
        } else {
            this._lastSearch = text;
            this._searchIndex = 0;
        }
        if (!text) return;
        var matches = this.element.find(":agile-blitem:contains("+text+")");
        matches.blitem("highlight", true);
        if (this._searchIndex >= matches.size()) this._searchIndex = 0;
        var topItem = matches.eq(this._searchIndex);
        if (topItem.size()) {
            topItem.blitem("bounce");
            var scrollTop = this.element.scrollTop();
            var lOffset = this.element.offset().top;
            var iOffset = topItem.offset().top;
            this.element.animate({scrollTop: scrollTop + iOffset - lOffset,});
        }
    },
});

$.widget("agile.blitem", {
    /**
     * Default options
     */
    options: {
        bug: {},
        _buglist: null,
    },
    /**
     * Initialize the widget
     */
    _create: function()
    {
        this.element.addClass("blitem");
        // toggle details visibility on click
        this.element.find("button.expand").button({
            icons: {primary: "ui-icon-circle-triangle-s"},
            text: false,
        }).click(function() {
            $(this).find(".ui-button-icon-primary").toggleClass(
                "ui-icon-circle-triangle-s ui-icon-circle-triangle-n");
            $(this).siblings(".details").slideToggle();
        });

        this._dList = this.element.find("ul.dependson").sortable();
        this._dList.addClass("buglist");
        this._setBuglist(this.options._buglist);
        this._updateBug();
    },
    /**
     * Destroy the widget
     */
    destroy: function()
    {
        this.element.removeClass("blitem blitem-hl")
        this._dList.sortable("destroy");
        $.Widget.prototype.destroy.apply(this);
    },

    /**
     * jQuery widget options setting method
     */
    _setOption: function(key, value)
    {
        $.Widget.prototype._setOption.apply( this, arguments );
        if (key == "bug") {
            this._updateBug();
        }
        if (key == "_buglist") {
            this._setBuglist(value);
        }
    },

    _setBuglist: function(buglist)
    {
        this._dList.sortable("option", {
            connectWith: buglist.options.connectWith,
            stop: $.proxy(buglist, "_onSortStop"),
            receive: $.proxy(buglist, "_onSortReceive"),
            update: $.proxy(buglist, "_onSortUpdate"),
        });
    },

    _updateBug:function()
    {
        var bug = this.options.bug;
        // Find each element with a title atribute and set the content from
        // matching bug property
        this.element.find("[title]").each(function() {
            var element = $(this);
            var key = element.attr("title");
            var value = bug[key];
            if (!$.isArray(value)) value = [value];
            for(var i = 0; i < value.length; i++) {
                element.text(value[i]);
                // Special cases
                if (["id", "depends_on", "blocks"].indexOf(key) > -1) {
                    element.attr("href", "show_bug.cgi?id=" + value[i]);
                }
                // If there is more values, clone the element
                if (i+1 < value.length) {
                    element.after(element.clone());
                    element = element.next();
                    element.before(", ");
                }
            }
        });
        if (bug.is_open) {
            this.element.removeClass("bz_closed");
        } else {
            this.element.addClass("bz_closed");
        }
    },

    addDepends: function(element)
    {
        var bug = element.blitem("bug");
        var place = null;
        var order = this.options._buglist.options.order;
        if (order) {
            this._dList.children(":agile-blitem").each(function() {
                var tmp = $(this).blitem("bug");
                if (tmp[order] > bug[order]) {
                    place = $(this);
                    return false;
                }
            });
        }
        if (place) {
            place.before(element);
        } else {
            this._dList.append(element);
        }
    },

    /**
     * Shortcut for blitem("option", "bug")
     */
    bug: function(bug)
    {
        if (bug) {
            this._setOption("bug", bug);
        } else {
            return this.options.bug;
        }
    },
    highlight: function(on) {
        if (on == null) {
            this.element.toggleClass("blitem-hl");
        } else if (on) {
            this.element.addClass("blitem-hl");
        } else {
            this.element.removeClass("blitem-hl");
        }
    },

    bounce: function()
    {
        var origMargin = this.element.css("margin-left");
        this.element.animate({"margin-left": "+=20"}, {queue: true})
                .animate({"margin-left": origMargin}, {queue: true});
    },

});
