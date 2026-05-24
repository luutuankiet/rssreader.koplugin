--[[ rssreader_story_menu_item.lua --
--
-- Custom menu item widget for rssreader's FreshRSS scan view.
-- Renders distinct title + optional divider + excerpt regions per row
-- (vs default Menu's single-blob multi-line text).
--
-- Pattern modeled after koreader/plugins/coverbrowser.koplugin/listmenu.lua
-- (ListMenuItem class), simplified for stories: no cover image, no shortcut
-- overlay, no dogear -- just typography.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local StoryMenuItem = InputContainer:extend{
    entry = nil,
    feed_label = nil,       -- short, dim, truncated source label (top-left)
    title_text = nil,       -- story title only (no feed prefix); allowed to wrap 2-3 lines
    excerpt_text = nil,
    mandatory = nil,        -- right-aligned (date)
    is_unread = false,
    show_parent = nil,
    menu = nil,
    width = nil,
    height = nil,
    dimen = nil,
    title_face_name = "infofont",
    excerpt_face_name = "smallinfofont",
    feed_label_face_name = "smallinfofont",
    show_divider = true,
    title_max_lines = 3,
    excerpt_max_lines = 4,
}

function StoryMenuItem:init()
    self.ges_events = {
        TapSelect = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
        HoldSelect = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        },
    }
    self.underline_h = 1
    self._underline_container = UnderlineContainer:new{
        vertical_align = "top",
        padding = 0,
        dimen = Geom:new{ w = self.width, h = self.height },
        linesize = self.underline_h,
    }
    self[1] = self._underline_container
    self:update()
end

function StoryMenuItem:update()
    local pad_h = Size.padding.fullscreen
    local pad_v = Size.padding.small
    local v_span = Size.span.vertical_large  -- 5px
    local inner_w = self.width - 2 * pad_h
    local inner_h = self.height - 2 * self.underline_h - 2 * pad_v

    local title_face = Font:getFace(self.title_face_name)
    local excerpt_face = Font:getFace(self.excerpt_face_name)
    local meta_face = Font:getFace(self.feed_label_face_name)

    -- Row 1 (metadata): feed_label (left, truncated) + date (right)
    local meta_row_widget
    local meta_row_h = 0
    if (self.feed_label and self.feed_label ~= "") or (self.mandatory and self.mandatory ~= "") then
        local mandatory_widget
        local mandatory_w = 0
        if self.mandatory and self.mandatory ~= "" then
            mandatory_widget = TextWidget:new{
                text = self.mandatory,
                face = meta_face,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }
            mandatory_w = mandatory_widget:getWidth() + Size.span.horizontal_default
        end
        local feed_label_w = inner_w - mandatory_w
        local feed_label_widget
        if self.feed_label and self.feed_label ~= "" then
            feed_label_widget = TextWidget:new{
                text = self.feed_label,
                face = meta_face,
                max_width = feed_label_w,
                truncate_with_ellipsis = true,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            }
        end
        local row_h = 0
        if feed_label_widget then row_h = math.max(row_h, feed_label_widget:getSize().h) end
        if mandatory_widget then row_h = math.max(row_h, mandatory_widget:getSize().h) end
        local left_slot, right_slot
        if feed_label_widget then
            left_slot = LeftContainer:new{
                dimen = Geom:new{ w = feed_label_w, h = row_h },
                feed_label_widget,
            }
        else
            left_slot = HorizontalSpan:new{ width = feed_label_w }
        end
        if mandatory_widget then
            right_slot = RightContainer:new{
                dimen = Geom:new{ w = mandatory_w - Size.span.horizontal_default, h = row_h },
                mandatory_widget,
            }
        end
        if right_slot then
            meta_row_widget = HorizontalGroup:new{
                align = "top",
                left_slot,
                HorizontalSpan:new{ width = Size.span.horizontal_default },
                right_slot,
            }
        else
            meta_row_widget = left_slot
        end
        meta_row_h = row_h
    end

    -- Row 2 (title): multi-line wrap, bold if unread; cap to title_max_lines
    local title_cap_h = nil
    if self.title_max_lines and self.title_max_lines > 0 then
        title_cap_h = self.title_max_lines * math.floor(title_face.size * 1.4)
    end
    local title_widget = TextBoxWidget:new{
        text = self.title_text or "",
        face = title_face,
        bold = self.is_unread,
        width = inner_w,
        alignment = "left",
        line_height = 0.2,
        height = title_cap_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    }
    local title_row_h = title_widget:getSize().h

    -- Divider
    local divider_widget
    local divider_h = 0
    if self.show_divider and self.excerpt_text and self.excerpt_text ~= "" then
        divider_widget = LineWidget:new{
            dimen = Geom:new{ w = math.floor(inner_w * 0.32), h = Size.line.thin },
            background = Blitbuffer.COLOR_DARK_GRAY,
        }
        divider_h = Size.line.thin
    end

    -- Excerpt: take remaining vertical room, capped to excerpt_max_lines
    local excerpt_widget
    if self.excerpt_text and self.excerpt_text ~= "" then
        local spans = (meta_row_h > 0 and v_span or 0) + 2 * v_span
        local excerpt_room = inner_h - meta_row_h - title_row_h - divider_h - spans
        local excerpt_cap_h = self.excerpt_max_lines and self.excerpt_max_lines > 0
            and (self.excerpt_max_lines * math.floor(excerpt_face.size * 1.4)) or excerpt_room
        local final_h = math.min(excerpt_room, excerpt_cap_h)
        if final_h > 0 then
            excerpt_widget = TextBoxWidget:new{
                text = self.excerpt_text,
                face = excerpt_face,
                width = inner_w,
                alignment = "left",
                line_height = 0.2,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                height = final_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
                italic = true,
            }
        end
    end

    local body = VerticalGroup:new{ align = "left" }
    if meta_row_widget then
        table.insert(body, meta_row_widget)
        table.insert(body, VerticalSpan:new{ width = v_span })
    end
    table.insert(body, title_widget)
    if divider_widget then
        table.insert(body, VerticalSpan:new{ width = v_span })
        table.insert(body, divider_widget)
        table.insert(body, VerticalSpan:new{ width = v_span })
    elseif excerpt_widget then
        table.insert(body, VerticalSpan:new{ width = v_span })
    end
    if excerpt_widget then
        table.insert(body, excerpt_widget)
    end

    local frame = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        padding_left = pad_h,
        padding_right = pad_h,
        padding_top = pad_v,
        padding_bottom = pad_v,
        body,
    }
    self._underline_container[1] = frame
end

function StoryMenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function StoryMenuItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    return true
end

function StoryMenuItem:onTapSelect(arg, ges)
    self.menu:onMenuSelect(self.entry)
    return true
end

function StoryMenuItem:onHoldSelect(arg, ges)
    self.menu:onMenuHold(self.entry)
    return true
end

return StoryMenuItem
