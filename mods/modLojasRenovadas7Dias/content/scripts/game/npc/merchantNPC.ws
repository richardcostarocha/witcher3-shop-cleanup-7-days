/***********************************************************************/
/** 	© 2015 CD PROJEKT S.A. All rights reserved.
/** 	THE WITCHER© is a trademark of CD PROJEKT S. A.
/** 	The Witcher game is based on the prose of Andrzej Sapkowski. 
/***********************************************************************/
struct MerchantNPCEmbeddedScenes
{
	editable var voiceTag        : name;
	editable var storyScene		 : CStoryScene;
	editable var input			 : name;
	editable var conditions : array<MerchantNPCEmbeddedScenesConditions>;
}

struct MerchantNPCEmbeddedScenesConditions
{
	editable var applyToTag    : name;
	editable var requiredFact  : string;
	editable var forbiddenFact : string;	
}


struct SWeeklyResaleEntry
{
    saved var item : SItemUniqueId;
    saved var itemName : name;
    saved var quantity : int;
    saved var paid : int;
}

struct SWeeklyResaleItemData
{
    var quantity : int;
    var paid : int;
    var cycle : int;
    var before : int;
}

class W3MerchantNPC extends CNewNPC
{
	private editable var        embeddedScenes : array<MerchantNPCEmbeddedScenes>;			
	private	saved var lastDayOfInteraction : int;
	public saved var questBonus : bool;
	editable var cacheMerchantMappin : bool;
	editable saved var craftingDisabled : bool;
	
	default cacheMerchantMappin = true;
	
	var invComp : CInventoryComponent;

	default questBonus = false;

	event OnSpawned( spawnData : SEntitySpawnData )
	{
		var tags : array< name >;
		var ids : array< SItemUniqueId >;
		var i : int;
		
		super.OnSpawned( spawnData );
		
		if ( theGame.IsActive() )
		{
			if ( !HasTag( 'ShopkeeperEntity' ) )
			{
				tags = GetTags();
				tags.PushBack( 'ShopkeeperEntity' );
				SetTags( tags );
			}
		}

		invComp = GetInventory();
		if ( invComp )
		{
			if ( spawnData.restored == true )
			{
				invComp.ClearTHmaps();
				invComp.ClearGwintCards();
				invComp.ClearKnownRecipes();
				if ( questBonus == true )
				{
					invComp.ActivateQuestBonus();
				}
			}
			else
			{
				invComp.SetupFunds();
				lastDayOfInteraction = GameTimeDays( theGame.GetGameTime() );
			}
			if ( invComp.GetMoney() == 0 )
			{
				invComp.SetupFunds();
			}
			invComp.GetAllItems(ids);
			for(i=0; i<ids.Size(); i+=1)
			{
				
				if ( invComp.GetItemModifierInt(ids[i], 'ItemQualityModified') <= 0 )
					invComp.AddRandomEnhancementToItem(ids[i]);
			}
		}
		else
		{
			Log( "<<< ERROR - W3MERCHANTNPC ATTEMPTED TO USE INVALID INVENTORY COMPONENT >>>" );
		}
    WeeklyMonitorSync();
	}

	public function ActivateQuestBonus()
	{
		var invComp : CInventoryComponent;
		invComp = GetInventory();

		if ( invComp )
		{
			invComp.ActivateQuestBonus();
		}
		questBonus = true;
	}

	public function HasEmbeddedScenes() : bool
	{
		if( embeddedScenes.Size() > 0)
			return true;
		else
			return false;
	}
	
	function GetEmbeddedSceneBlocked( conditions : array<MerchantNPCEmbeddedScenesConditions> ) : bool
	{
		var size : int;
		var i : int;
		
		size = conditions.Size();
		
		if( size == 0 )return false;
		
		for( i=0; i < size; i+= 1)
		{
			if( this.HasTag( conditions[i].applyToTag ) || conditions[i].applyToTag == '' )
			{
				if(  (conditions[i].requiredFact != "" && FactsQuerySum( conditions[i].requiredFact ) == 0 ) || ( FactsQuerySum( conditions[i].forbiddenFact ) >= 1 ) )
					return true;
			}
		}
		
		return false;
	}
	
	function StartEmbeddedScene() : bool
	{
		var voiceTag : name;
		var i : int;
		
		voiceTag = GetVoicetag();
		
		if( voiceTag )
		{
			for( i = 0; i < embeddedScenes.Size(); i+=1 )
			{
				if( embeddedScenes[i].voiceTag == voiceTag )
				{
					if( GetEmbeddedSceneBlocked( embeddedScenes[i].conditions ) )
					{
						return false;
					}
					else
					{
						theGame.GetStorySceneSystem().PlayScene( embeddedScenes[i].storyScene, embeddedScenes[i].input );
						return true;
					}
				}
			}
		}
		
		return false;
	}
	
	function HasValidEmbeddedScene() : bool
	{
		var voiceTag : name;
		var i : int;
		
		voiceTag = GetVoicetag();
		
		if( embeddedScenes.Size() <= 0 )
			return false;
		
		if( voiceTag )
		{
			for( i = 0; i < embeddedScenes.Size(); i+=1 )
			{
				if( embeddedScenes[i].voiceTag == voiceTag )
				{
					if( GetEmbeddedSceneBlocked( embeddedScenes[i].conditions ) )
						return false;
					else
						return true;
				}
			}
		}
		
		return false;
	}
	
	event OnInteraction( actionName : string, activator : CEntity )
	{	
		var ciriEntity  		: W3ReplacerCiri;
		var	isPlayingChatScene	: bool;
		var timeElapsed : int;
		var gameTimeDay : int;

		LogChannel( 'DialogueTest', "Event Interaction Used" );
		if ( actionName == "Talk" )
		{
			invComp = GetInventory();
			if ( invComp )
			{
				gameTimeDay = GameTimeDays( theGame.GetGameTime() );
				timeElapsed = gameTimeDay - lastDayOfInteraction;

				if ( timeElapsed >= invComp.GetDaysToIncreaseFunds() || timeElapsed < 0 )
				{
					invComp.IncreaseFunds();
					lastDayOfInteraction = gameTimeDay;
				}
				WeeklyResumeNativeLoot();
				WeeklyProcessResale();
                WeeklyMonitorSync();
			}
			else
			{
				Log( "<<< ERROR - W3MERCHANTNPC ATTEMPTED TO USE INVALID INVENTORY COMPONENT >>>" );
			}

			LogChannel( 'DialogueTest', "Activating TALK Interaction - PLAY DIALOGUE" );
			isPlayingChatScene = IsPlayingChatScene();
			
			
			if ( HasEmbeddedScenes() )
			{
				if ( !isPlayingChatScene )
				{
				
					if ( !PlayDialog() )
					{
						
						ciriEntity = (W3ReplacerCiri)thePlayer;
						if ( ciriEntity )
						{
							EnableDynamicLookAt( thePlayer, 5 );
						}
						else
						{
							
							if ( !StartEmbeddedScene() )
							{
								super.OnInteraction( actionName, activator);
							}
						}
					}
				}
			}
			else
			{
				super.OnInteraction( actionName, activator);
			}
		}
	}

	
	event OnInteractionActivationTest( interactionComponentName : string, activator : CEntity )
	{
		if( HasEmbeddedScenes() && interactionComponentName == "talk" )
		{
			if( activator == thePlayer && ( thePlayer.CanStartTalk() || HasValidEmbeddedScene() ) && !wasInTalkInteraction )
			{
				return true;
			}
		}
		
		return super.OnInteractionActivationTest( interactionComponentName, activator );
	}
	
	public function IsCraftingDisabled() : bool
	{
		return craftingDisabled;
	}
	
	public function SetCraftingEnabled( enable : bool )
	{
		craftingDisabled = !enable;
	}
    // Old saved fields remain readable, but old IDs are not proof of ownership.
    private saved var weeklyResaleEntries : array<SWeeklyResaleEntry>;
    private saved var weeklyResaleStarted : bool;
    private saved var weeklyResaleTime : int;
    private var weeklyResaleNotice : string;
    private saved var weeklyResaleCancelledByDeath : bool;

    event OnDeath(damageAction : W3DamageAction)
    {
        var permanentDeath : bool;
        permanentDeath = !WillBeUnconscious();
        // Preserve native death, quest, experience and loot processing.
        super.OnDeath(damageAction);
        if (permanentDeath && !IsAlive())
            WeeklyCancelOnDeath();
    }

    // Exclude only the verified Kaer Trolde harbor role, across its recreated actors.
    public function WeeklyIsResaleExcluded() : bool
    {
        return HasTag('kaer_trolde_herbalist_01');
    }

    private function WeeklyStripExcludedItemMarkers(inventory : CInventoryComponent, item : SItemUniqueId)
    {
        if (!inventory || !inventory.IsIdValid(item))
            return;
        // Leave ordinary items untouched. Clear only this mod's nonzero metadata.
        if (inventory.GetItemModifierInt(item, 'LR7Sale', 0) != 0
            || inventory.GetItemModifierInt(item, 'LR7Quantity', 0) != 0
            || inventory.GetItemModifierInt(item, 'LR7Paid', 0) != 0
            || inventory.GetItemModifierInt(item, 'LR7Cycle', 0) != 0)
            WeeklyClearSale(inventory, item);
    }

    public function WeeklyPrepareResaleExclusion()
    {
        var inventory : CInventoryComponent;
        var items : array<SItemUniqueId>;
        var i : int;
        if (!WeeklyIsResaleExcluded())
            return;
        inventory = GetInventory();
        if (inventory)
        {
            inventory.GetAllItems(items);
            for (i = 0; i < items.Size(); i += 1)
                WeeklyStripExcludedItemMarkers(inventory, items[i]);
        }
        weeklyResaleEntries.Clear();
        weeklyResaleStarted = false;
        weeklyResaleTime = 0;
        RemoveTimer('WeeklyShowReceipt');
        weeklyResaleNotice = "";
        WeeklyResumeNativeLoot();
        // Old orphan summary rows cannot be identified by generic name/voice.
        // Keep their slots intact; use the existing explicit panel cancellation.
    }

    private function WeeklyClearDeathMarkers()
    {
        var inventory : CInventoryComponent;
        var items : array<SItemUniqueId>;
        var i : int;
        inventory = GetInventory();
        if (inventory)
        {
            inventory.GetAllItems(items);
            for (i = 0; i < items.Size(); i += 1)
                if (inventory.GetItemModifierInt(items[i], 'LR7Sale', 0) == 1)
                    WeeklyClearSale(inventory, items[i]);
        }
        weeklyResaleEntries.Clear();
        weeklyResaleStarted = false;
        weeklyResaleTime = 0;
    }

    private function WeeklyCancelOnDeath()
    {
        if (WeeklyIsResaleExcluded())
        {
            WeeklyPrepareResaleExclusion();
            return;
        }
        // Sync before setting the cancellation, while old pending marks can be read.
        WeeklyMonitorSync();
        weeklyResaleCancelledByDeath = true;
        theGame.WeeklyMonitorMarkDeath(weeklyResaleMonitorSlot);
        WeeklyClearDeathMarkers();
        RemoveTimer('WeeklyShowReceipt');
        weeklyResaleNotice = "";
        WeeklyResumeNativeLoot();
        WeeklyQueueNotice("Revenda: pendencias de " + GetDisplayName(false)
            + " canceladas por morte do vendedor. Sem retorno de coroas.");
    }

    private function WeeklyResaleAllowed(item : SItemUniqueId) : bool
    {
        var inventory : CInventoryComponent;
        if (WeeklyIsResaleExcluded())
            return false;
        inventory = GetInventory();
        if (!inventory || !inventory.IsIdValid(item))
            return false;
        if (inventory.IsItemQuest(item) || inventory.ItemHasTag(item, 'Quest')
            || inventory.ItemHasTag(item, 'QuestEP1') || inventory.ItemHasTag(item, 'QuestEP2')
            || inventory.ItemHasTag(item, 'NoDrop')
            || inventory.ItemHasTag(item, theGame.params.TAG_DONT_SHOW)
            || inventory.IsItemMounted(item) || inventory.IsItemHeld(item))
            return false;
        if (inventory.GetItemName(item) == 'Crowns' || inventory.IsItemFists(item)
            || inventory.GetItemCategory(item) == 'gwint'
            || inventory.ItemHasTag(item, 'ThMap')
            || inventory.IsRecipeOrSchematic(item))
            return false;
        return true;
    }

    public function WeeklyReadSale(item : SItemUniqueId) : SWeeklyResaleItemData
    {
        var inventory : CInventoryComponent;
        var saleData : SWeeklyResaleItemData;
        if (WeeklyIsResaleExcluded())
            return saleData;
        inventory = GetInventory();
        if (!inventory || !inventory.IsIdValid(item)
            || inventory.GetItemModifierInt(item, 'LR7Sale', 0) != 1)
            return saleData;
        saleData.quantity = inventory.GetItemModifierInt(item, 'LR7Quantity', 0);
        saleData.paid = inventory.GetItemModifierInt(item, 'LR7Paid', 0);
        saleData.cycle = inventory.GetItemModifierInt(item, 'LR7Cycle', 0);
        saleData.before = inventory.GetItemQuantity(item);
        if (saleData.quantity <= 0 || saleData.paid < 0 || saleData.cycle < 0)
        {
            saleData.quantity = 0;
            saleData.paid = 0;
            saleData.cycle = 0;
            saleData.before = 0;
        }
        return saleData;
    }

    public function WeeklyClearSale(inventory : CInventoryComponent, item : SItemUniqueId)
    {
        if (!inventory || !inventory.IsIdValid(item))
            return;
        inventory.SetItemModifierInt(item, 'LR7Sale', 0);
        inventory.SetItemModifierInt(item, 'LR7Quantity', 0);
        inventory.SetItemModifierInt(item, 'LR7Paid', 0);
        inventory.SetItemModifierInt(item, 'LR7Cycle', 0);
    }

    public function WeeklyWriteSale(item : SItemUniqueId, saleData : SWeeklyResaleItemData)
    {
        var inventory : CInventoryComponent;
        var available : int;
        inventory = GetInventory();
        if (!inventory || !inventory.IsIdValid(item))
            return;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyStripExcludedItemMarkers(inventory, item);
            return;
        }
        available = inventory.GetItemQuantity(item);
        if (saleData.quantity > available && saleData.quantity > 0)
        {
            saleData.paid = (int)((float)saleData.paid * (float)available / (float)saleData.quantity);
            saleData.quantity = available;
        }
        if (saleData.quantity <= 0 || saleData.paid < 0 || saleData.cycle < 0)
        {
            WeeklyClearSale(inventory, item);
            return;
        }
        inventory.SetItemModifierInt(item, 'LR7Sale', 1);
        inventory.SetItemModifierInt(item, 'LR7Quantity', saleData.quantity);
        inventory.SetItemModifierInt(item, 'LR7Paid', saleData.paid);
        inventory.SetItemModifierInt(item, 'LR7Cycle', saleData.cycle);
    }

    private function WeeklyRestoreClock()
    {
        var inventory : CInventoryComponent;
        var items : array<SItemUniqueId>;
        var saleData : SWeeklyResaleItemData;
        var i : int;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyPrepareResaleExclusion();
            return;
        }
        inventory = GetInventory();
        if (!inventory)
            return;
        WeeklyBindMonitorSlot();
        // Also reconcile restored NPC inventories against the saved death cancellation.
        if (weeklyResaleCancelledByDeath
            || theGame.WeeklyMonitorWasCancelledByDeath(weeklyResaleMonitorSlot))
        {
            weeklyResaleCancelledByDeath = true;
            WeeklyClearDeathMarkers();
            return;
        }
        if (theGame.WeeklyMonitorHasManualCancel(weeklyResaleMonitorSlot))
        {
            // Clear stale marks before reading, paying, buying back or recording new sales.
            // The request stays saved until this inventory can actually be reconciled.
            WeeklyClearDeathMarkers();
            RemoveTimer('WeeklyShowReceipt');
            weeklyResaleNotice = "";
            WeeklyResumeNativeLoot();
            theGame.WeeklyMonitorAcknowledgeCancel(weeklyResaleMonitorSlot);
        }
        // Never bind a pre-0.4.2 record to another item by its saved ID or name.
        weeklyResaleEntries.Clear();
        // Only valid item records establish a pending resale cycle.
        weeklyResaleStarted = false;
        weeklyResaleTime = 0;
        inventory.GetAllItems(items);
        for (i = 0; i < items.Size(); i += 1)
        {
            saleData = WeeklyReadSale(items[i]);
            if (saleData.quantity > 0
                && (!weeklyResaleStarted || saleData.cycle < weeklyResaleTime))
            {
                weeklyResaleStarted = true;
                weeklyResaleTime = saleData.cycle;
            }
        }
    }

    private function WeeklySetMarkedClock(now : int)
    {
        var inventory : CInventoryComponent;
        var items : array<SItemUniqueId>;
        var saleData : SWeeklyResaleItemData;
        var i : int;
        inventory = GetInventory();
        if (!inventory)
            return;
        inventory.GetAllItems(items);
        for (i = 0; i < items.Size(); i += 1)
        {
            saleData = WeeklyReadSale(items[i]);
            if (saleData.quantity > 0)
                inventory.SetItemModifierInt(items[i], 'LR7Cycle', now);
        }
    }

    private function WeeklyPendingQuantity() : int
    {
        var inventory : CInventoryComponent;
        var items : array<SItemUniqueId>;
        var saleData : SWeeklyResaleItemData;
        var i, total : int;
        inventory = GetInventory();
        if (!inventory)
            return 0;
        inventory.GetAllItems(items);
        total = 0;
        for (i = 0; i < items.Size(); i += 1)
        {
            saleData = WeeklyReadSale(items[i]);
            if (saleData.quantity > saleData.before)
                saleData.quantity = saleData.before;
            total += saleData.quantity;
        }
        return total;
    }

    private function WeeklyQueueNotice(message : string)
    {
        if (WeeklyIsResaleExcluded())
            return;
        weeklyResaleNotice = message;
        LogChannel('WeeklyResale', message);
        RemoveTimer('WeeklyShowReceipt');
        AddTimer('WeeklyShowReceipt', 1.0f, true);
    }

    private timer function WeeklyShowReceipt(delta : float, id : int)
    {
        if (theGame.IsDialogOrCutscenePlaying() || theGame.IsBlackscreenOrFading()
            || theGame.GetGuiManager().IsAnyMenu())
            return;
        RemoveTimer('WeeklyShowReceipt');
        if (weeklyResaleNotice != "" && GetWitcherPlayer())
            GetWitcherPlayer().DisplayHudMessage(weeklyResaleNotice);
        weeklyResaleNotice = "";
    }

    public function WeeklyRecordSale(item : SItemUniqueId, quantity : int, paid : int)
    {
        var saleData : SWeeklyResaleItemData;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyPrepareResaleExclusion();
            return;
        }
        if (weeklyResaleCancelledByDeath || !IsAlive())
            return;
        if (quantity <= 0 || paid < 0 || !WeeklyResaleAllowed(item))
            return;
        WeeklyRestoreClock();
        if (!weeklyResaleStarted)
        {
            weeklyResaleStarted = true;
            weeklyResaleTime = GameTimeToSeconds(theGame.GetGameTime());
        }
        saleData = WeeklyReadSale(item);
        saleData.quantity += quantity;
        saleData.paid += paid;
        saleData.cycle = weeklyResaleTime;
        WeeklyWriteSale(item, saleData);
        WeeklyQueueNotice("Revenda: " + WeeklyPendingQuantity()
            + " itens registrados nesta loja. Prazo: 7 dias; retorno: 125%.");
        WeeklyMonitorSync();
    }

    // Snapshot and clear before transfer; success restores only the remainder.
    public function WeeklyRecordBuyback(item : SItemUniqueId, quantity : int,
        saleData : SWeeklyResaleItemData, customerInventory : CInventoryComponent,
        customerItem : SItemUniqueId)
    {
        var inventory : CInventoryComponent;
        var after, removed, remaining : int;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyPrepareResaleExclusion();
            WeeklyStripExcludedItemMarkers(customerInventory, customerItem);
            return;
        }
        inventory = GetInventory();
        if (!inventory || saleData.quantity <= 0 || quantity <= 0)
            return;
        WeeklyClearSale(customerInventory, customerItem);
        after = 0;
        if (inventory.IsIdValid(item))
            after = inventory.GetItemQuantity(item);
        removed = saleData.before - after;
        if (removed > quantity)
            removed = quantity;
        if (removed < 0)
            removed = 0;
        remaining = saleData.quantity - removed;
        if (remaining < 0)
            remaining = 0;
        saleData.paid = (int)((float)saleData.paid * (float)remaining / (float)saleData.quantity);
        saleData.quantity = remaining;
        WeeklyWriteSale(item, saleData);
        WeeklyQueueNotice("Revenda: recompra registrada; " + WeeklyPendingQuantity()
            + " itens ainda aguardam revenda nesta loja.");
        WeeklyMonitorSync();
    }

    private function WeeklyProcessResale()
    {
        var inventory : CInventoryComponent;
        var items : array<SItemUniqueId>;
        var item : SItemUniqueId;
        var saleData : SWeeklyResaleItemData;
        var now, i, quantity, before, removed, soldCount, revenue, hours : int;
        var paidTotal : float;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyPrepareResaleExclusion();
            return;
        }
        if (!GetWitcherPlayer())
            return;
        inventory = GetInventory();
        if (!inventory)
            return;
        WeeklyRestoreClock();
        if (weeklyResaleCancelledByDeath || !IsAlive())
            return;
        now = GameTimeToSeconds(theGame.GetGameTime());
        if (!weeklyResaleStarted)
        {
            WeeklyQueueNotice("Revenda: nenhuma venda registrada nesta loja.");
            return;
        }
        if (now < weeklyResaleTime)
        {
            weeklyResaleTime = now;
            WeeklySetMarkedClock(now);
            return;
        }
        if (now - weeklyResaleTime < 604800)
        {
            hours = (604800 - (now - weeklyResaleTime) + 3599) / 3600;
            WeeklyQueueNotice("Revenda: " + WeeklyPendingQuantity()
                + " itens registrados nesta loja; faltam " + hours + " horas para a rodada.");
            return;
        }
        paidTotal = 0.0f;
        soldCount = 0;
        inventory.GetAllItems(items);
        for (i = 0; i < items.Size(); i += 1)
        {
            item = items[i];
            saleData = WeeklyReadSale(item);
            if (saleData.quantity <= 0 || !WeeklyResaleAllowed(item))
                continue;
            before = inventory.GetItemQuantity(item);
            quantity = saleData.quantity;
            if (quantity > before)
                quantity = before;
            if (quantity <= 0)
                continue;
            inventory.RemoveItem(item, quantity);
            if (inventory.IsIdValid(item))
                removed = before - inventory.GetItemQuantity(item);
            else
                removed = before;
            if (removed <= 0)
                continue;
            if (removed > quantity)
                removed = quantity;
            paidTotal += (float)saleData.paid * (float)removed / (float)saleData.quantity;
            soldCount += removed;
            saleData.paid = (int)((float)saleData.paid
                * (float)(saleData.quantity - removed) / (float)saleData.quantity);
            saleData.quantity -= removed;
            WeeklyWriteSale(item, saleData);
        }
        revenue = (int)(paidTotal * 1.25f);
        if (revenue > 0 && inventory.GetFundsType() != EInventoryFunds_Unlimited)
            inventory.AddMoney(revenue);
        weeklyResaleTime = now;
        WeeklySetMarkedClock(now);
        WeeklyQueueNotice("Revenda: " + soldCount + " itens revendidos (+"
            + revenue + " coroas). Pendentes: " + WeeklyPendingQuantity() + ".");
    }

    // Native stock regeneration can discard player-sold ingredient stacks.
    // Keep those items in this inventory until resale or complete buyback.
    // This query deliberately does not process another weekly round.
    public function WeeklyCanRefreshStock() : bool
    {
        if (WeeklyIsResaleExcluded())
            return true;
        return WeeklyPendingQuantity() == 0;
    }


    // Runtime-only pause: never change food UI or persist a resale lock.
    private var weeklyLootPaused : bool;

    public function WeeklyPauseNativeLoot()
    {
        var inventory : CInventoryComponent;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyResumeNativeLoot();
            return;
        }
        inventory = GetInventory();
        if (!inventory || WeeklyCanRefreshStock() || weeklyLootPaused)
            return;
        inventory.EnableLoot(false);
        weeklyLootPaused = true;
        AddTimer('WeeklyResumeLootFallback', 1.0f, true);
    }

    public function WeeklyResumeNativeLoot()
    {
        var inventory : CInventoryComponent;
        if (!weeklyLootPaused)
            return;
        inventory = GetInventory();
        if (inventory)
            inventory.EnableLoot(true);
        weeklyLootPaused = false;
        RemoveTimer('WeeklyResumeLootFallback');
    }

    private timer function WeeklyResumeLootFallback(delta : float, id : int)
    {
        if (!theGame.IsDialogOrCutscenePlaying() && !theGame.GetGuiManager().IsAnyMenu())
            WeeklyResumeNativeLoot();
    }


    private saved var weeklyResaleMonitorSlot : int;

    private var weeklyReferenceLabel : string;
    private var weeklyReferencePosition : Vector;

    private function WeeklyBindMonitorSlot()
    {
        var lootManager : CR4LootManager;
        var area, identity : string;
        area = "";
        lootManager = theGame.GetLootManager();
        if (lootManager)
            area = lootManager.GetCurrentArea();
        identity = area + "_" + GetGuidHash();
        weeklyResaleMonitorSlot = theGame.WeeklyMonitorResolveSlot(weeklyResaleMonitorSlot, identity);
    }

    private function WeeklyMonitorReference() : string
    {
        var manager : CCommonMapManager;
        var pins : array<SCommonMapPinInstance>;
        var i : int;
        var position : Vector;
        var distanceSquared, bestDistance : float;
        var label, bestLabel : string;
        if (WeeklyPendingQuantity() <= 0)
            return "";
        position = GetWorldPosition();
        // Cache a valid reference until this merchant moves over 100 world units.
        if (weeklyReferenceLabel != ""
            && VecDistanceSquared2D(position, weeklyReferencePosition) < 10000.0f)
            return weeklyReferenceLabel;
        manager = theGame.GetCommonMapManager();
        if (!manager || !theGame.GetWorld())
            return "";
        pins = manager.GetMapPinInstances(theGame.GetWorld().GetDepotPath());
        bestDistance = 1000000.0f;
        bestLabel = "";
        for (i = 0; i < pins.Size(); i += 1)
        {
            if (pins[i].type != 'RoadSign' || !pins[i].isDiscovered || pins[i].isDisabled)
                continue;
            distanceSquared = VecDistanceSquared2D(position, pins[i].position);
            if (distanceSquared >= bestDistance)
                continue;
            // Same localisation rule used by the native map menu.
            label = GetLocStringByKeyExt(StrLower("map_location_" + pins[i].tag));
            if (label == "")
                continue;
            bestDistance = distanceSquared;
            bestLabel = label;
        }
        weeklyReferencePosition = position;
        weeklyReferenceLabel = bestLabel;
        return bestLabel;
    }

    private function WeeklyMonitorSync()
    {
        var lootManager : CR4LootManager;
        var mapManager : CCommonMapManager;
        var journalArea : name;
        var area, identity : string;
        if (WeeklyIsResaleExcluded())
        {
            WeeklyPrepareResaleExclusion();
            return;
        }
        if (!GetInventory() || !GetWitcherPlayer())
            return;
        WeeklyRestoreClock();
        area = "";
        lootManager = theGame.GetLootManager();
        if (lootManager)
            area = lootManager.GetCurrentArea();
        // Preserve the existing identity key; display area is separate.
        identity = area + "_" + GetGuidHash();
        area = "";
        mapManager = theGame.GetCommonMapManager();
        if (mapManager)
        {
            journalArea = mapManager.GetCurrentJournalAreaByPosition(GetWorldPosition());
            area = GetLocStringByKeyExt(mapManager.GetLocalisationNameFromAreaType(journalArea));
            if (area == "")
                area = NameToString(journalArea);
        }
        weeklyResaleMonitorSlot = theGame.WeeklyMonitorUpdate(
            weeklyResaleMonitorSlot, identity, GetDisplayName(false), area,
            WeeklyPendingQuantity(), weeklyResaleTime, NameToString(GetVoicetag()),
            WeeklyMonitorReference());
    }

}
