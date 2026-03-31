//
//  SyncWidgetBundle.swift
//  SyncWidget
//
//  Created by JungHwan Yun on 3/31/26.
//

import WidgetKit
import SwiftUI

@main
struct SyncWidgetBundle: WidgetBundle {
    var body: some Widget {
        SyncWidget()
        SyncWidgetLiveActivity()
    }
}
