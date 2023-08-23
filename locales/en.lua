local Translations = {
    success = {
        boughtProperty = 'You bought the property for $%{price}',
        soldProperty = 'You sold the property for $%{price}',
    },
    error = {
        playernotonline = 'Player is not online',
        failed_createproperty = 'Failed to create property',
        players_nearby = 'There are no players nearby!',
        cancelled = 'Cancelled',
        problem = 'There was a problem',
        offerDenied = 'Offer denied',
        notenoughmoney = 'The person does not have enough money',
    },
    general = {
        accept = 'Accept',
        decline = 'Decline',
        openwardrobe = '[E] - Open Wardrobe',
        exit = '[E] - Exit',
        openstash = '[E] - Open Stash',
        stashname = 'Apartment Storage',
        logout = '[E] - Logout',
        ipl = 'Furnished',
        shell = 'Unfurnished',
        garage = 'Garage',
        none = 'None',
    },
    create_property_menu = {
        title = 'Create Property',
        interior_label_garage = '%{interior} (%{slots} slots)',
        interior_label = '%{interior}',
    },
    properties_menu = {
        garage = 'Garage',
        ipl = 'Property',
        showmenuhelp = '~g~E~w~ - Enter %{propertyType}',
    },
    property_menu = {
        visit = 'Visit',
        rent = 'Rent',
        rent_desc = 'Rent property to someone for $%{price}?',
        sell = 'Sell',
        sell_desc = 'Sell property to someone for $%{price}?',
        ring = 'Ring Doorbell',
        enter = 'Enter Property',
        modify = 'Modify Property',
        extend_rent = 'Extend Rent',
        extend_rent_desc = 'Rent expires in %{rent_expiration} days, extend for $%{price}?',
        back = 'Back',
    },
    modify_property_menu = {
        title = 'Modify Property',
        name = 'Name: %{name}',
        price = 'Price: %{price}',
        rent = 'Rent Price: %{price}',
        property_type = 'Type: %{property_type}',
        interior = 'Interior: %{interior}',
        storage = {
            slots = "Slots: %{value}",
            maxweight = "Max weight: %{value} Kg",
        },
        taxes = 'Taxes: %{taxes}',
        done = 'Done',
    },
    manage_property_menu = {
    },
}

Lang = Lang or Locale:new({
    phrases = Translations,
    warnOnMissing = true
})