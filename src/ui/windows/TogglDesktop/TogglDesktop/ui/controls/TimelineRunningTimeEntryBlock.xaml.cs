﻿using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using TogglDesktop.ViewModels;

namespace TogglDesktop
{
    /// <summary>
    /// Interaction logic for TimelineRunningTimeEntryBlock.xaml
    /// </summary>
    public partial class TimelineRunningTimeEntryBlock : UserControl
    {
        public TimeEntryBlock ViewModel
        {
            get => DataContext as TimeEntryBlock;
            set => DataContext = value;
        }

        private TimelineTimeEntryBlockPopup _popup;
        public TimelineTimeEntryBlockPopup PopupContainer => _popup ??= new TimelineTimeEntryBlockPopup();

        public TimelineRunningTimeEntryBlock()
        {
            InitializeComponent();
        }
        private void OnThumbTopDragDelta(object sender, DragDeltaEventArgs e)
        {
            if (ViewModel.Height - e.VerticalChange > 0)
            {
                ViewModel.VerticalOffset += e.VerticalChange;
                ViewModel.Height -= e.VerticalChange;
            }
        }

        private void OnThumbTopDragCompleted(object sender, DragCompletedEventArgs e)
        {
            ViewModel.ChangeStartTime();
            ViewModel.IsDragged = false;
        }

        private void OnThumbDragStarted(object sender, DragStartedEventArgs e)
        {
            ViewModel.IsDragged = true;
        }
    }
}